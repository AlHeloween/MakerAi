"""Read the semantic-vector trajectory from Claude Code session transcripts.

    python tools/claude_svchain.py --list
    python tools/claude_svchain.py <session-id-or-path>
    python tools/claude_svchain.py <session-id-or-path> --grep topic
    python tools/claude_svchain.py <session-id-or-path> --full

Sibling of tools/codex_svchain.py — same contract, different host: this one reads
~/.claude/projects/<slugged-cwd>/*.jsonl instead of Codex rollouts.

The chain shows topic order and broken links, not the reasoning at a fork.
Read the located transcript and its artifacts to understand a decision.
This program only reads session files.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


ZERO = "0" * 32
KEYWORDS = re.compile(r"^Keywords:\s*(.+)$")
DOMINANT = re.compile(r"^Semantic dominant:\s*(.+)$")
OWN = re.compile(r"^md5:\s*([0-9a-fA-F]{32})$")
PREV = re.compile(r"^prev-md5:\s*([0-9a-fA-F]{32})$")
PARENT = re.compile(r"^parent-goal-md5:\s*([0-9a-fA-F]{32})$")
PHASE = re.compile(r"^phase:\s*([A-Za-z]+)$")


def _vector_from(found: dict):
    """Normalise one parsed field set, or None when a required field is missing.

    A partial block is rejected rather than half-parsed: a vector with no own id
    cannot be linked to, and one with no prev id cannot be checked for a break,
    so admitting it would silently weaken every edge after it.
    """
    if len(found) < 5:
        return None
    # phase is OPTIONAL: the kernel asks for two blocks per turn (intent at the
    # start, actual at the end), but every block written before that rule has no
    # phase line and must keep reading as the turn's ACTUAL vector.
    phase = (found.get("phase") or "actual").lower()
    if phase not in ("intent", "actual"):
        phase = "actual"
    return {
        "keywords": found["keywords"],
        "dominant": found["dominant"],
        "own": found["own"].lower(),
        "prev": found["prev"].lower(),
        "parent": found["parent"].lower(),
        "phase": phase,
    }


def vectors_in(text: str) -> list[dict]:
    """EVERY vector in one text, in order.

    A single assistant message may carry TWO blocks (intent at the start, actual
    at the end). Parsing only the first dropped the actual, so the report printed
    `actual (none)` and invented a chain break at every such turn — measured
    2026-10-25 on the Legislator's transcript, turns 21-25. A repeated field line
    (`Keywords:` after a complete block) starts the next block.
    """
    out: list[dict] = []
    found: dict = {}
    for line in text.splitlines():
        for name, pattern in (
            ("keywords", KEYWORDS), ("dominant", DOMINANT),
            ("own", OWN), ("prev", PREV), ("parent", PARENT), ("phase", PHASE),
        ):
            match = pattern.match(line.strip())
            if not match:
                continue
            if name in found:            # the field repeats -> this is the next block
                vector = _vector_from(found)
                if vector:
                    out.append(vector)
                found = {}
            found[name] = match.group(1).strip()
            break
    vector = _vector_from(found)
    if vector:
        out.append(vector)
    return out


def vector_in(text: str):
    """The FIRST vector in one text, or None (kept for callers that want one)."""
    found = vectors_in(text)
    return found[0] if found else None


def vectors(path: Path) -> list[dict]:
    """Every vector in one transcript, in order."""
    chain: list[dict] = []
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = row.get("message")
            if not isinstance(message, dict) or message.get("role") != "assistant":
                continue
            content = message.get("content")
            blocks = [content] if isinstance(content, str) else content
            if not isinstance(blocks, list):
                continue
            for block in blocks:
                text = block if isinstance(block, str) else (
                    block.get("text") if isinstance(block, dict) and block.get("type") == "text" else None
                )
                if not isinstance(text, str):
                    continue
                chain.extend(vectors_in(text))
    return chain


def format_chain(chain: list[dict], needle: str | None = None, full: bool = False) -> list[str]:
    """Numbered lines with edge status. A filter narrows what PRINTS, never the
    numbering and never the edge check — an edge is always compared against the
    real predecessor in the full stream, or a filtered view would invent breaks.

    With full=True each vector prints its whole block — keywords, dominant and the
    lineage — so the printed chain can be read back by this same tool."""
    lines: list[str] = []
    for index, vector in enumerate(chain):
        if index == 0 or vector["prev"] == ZERO:
            edge = "[RESET]" if vector["prev"] == ZERO else "[START]"
        elif vector["prev"] == chain[index - 1]["own"]:
            edge = "[LINK]"
        else:
            edge = f"[BREAK expected={chain[index - 1]['own'][:8]} got={vector['prev'][:8]}]"
        if needle and needle.lower() not in vector["dominant"].lower() \
                and needle.lower() not in vector["keywords"].lower():
            continue
        lines.append(f"{index + 1:>4} {edge}")
        if full:
            lines.append(f"     Keywords: {vector['keywords']}")
            lines.append(f"     phase: {vector['phase']}")
            lines.append(f"     Semantic dominant: {vector['dominant']}")
            lines.append(f"     md5: {vector['own']}")
            lines.append(f"     prev-md5: {vector['prev']}")
            lines.append(f"     parent-goal-md5: {vector['parent']}")
        else:
            lines.append(f"     {vector['dominant']}")
    return lines


def weights(keywords: str) -> dict[str, float]:
    """'topic 0.35, other 0.20' -> {'topic': 0.35, 'other': 0.20}."""
    out: dict[str, float] = {}
    for chunk in keywords.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        term, _, raw = chunk.rpartition(" ")
        if not term:
            continue
        try:
            out[term.strip()] = float(raw)
        except ValueError:
            continue
    return out


def l1(left: dict[str, float], right: dict[str, float]) -> float:
    """Manhattan distance over the union of the named keyword axes."""
    return sum(abs(left.get(term, 0.0) - right.get(term, 0.0)) for term in set(left) | set(right))


def turns(chain: list[dict]) -> list[dict]:
    """Group the stream into turns: an intent opens one, an actual closes it.

    A legacy block (no phase, read as actual) opens its own turn, so the report
    still numbers every turn the transcript contains.
    """
    grouped: list[dict] = []
    for vector in chain:
        if vector["phase"] == "intent":
            grouped.append({"intent": vector, "actual": None})
            continue
        if grouped and grouped[-1]["actual"] is None:
            grouped[-1]["actual"] = vector
        else:
            grouped.append({"intent": None, "actual": vector})
    return grouped


def report(chain: list[dict]) -> list[str]:
    """Per turn: the two ids, drift (intent vs actual) and continuity (actual vs
    the previous turn's actual), plus the phase-derived chain edge.

    A missing intent prints `drift: n/a (no intent)` — never 0, which would read
    as a perfect match that was never measured. Same for a first turn's continuity.
    """
    lines: list[str] = []
    previous_actual = None
    for index, turn in enumerate(turns(chain), start=1):
        intent, actual = turn["intent"], turn["actual"]
        lines.append("%4d intent %-8s actual %-8s" % (
            index,
            intent["own"][:8] if intent else "(none)",
            actual["own"][:8] if actual else "(none)",
        ))
        if intent and actual:
            drift = "%.2f" % l1(weights(intent["keywords"]), weights(actual["keywords"]))
        else:
            drift = "n/a (no intent)" if not intent else "n/a (no actual)"
        if actual and previous_actual:
            continuity = "%.2f" % l1(weights(previous_actual["keywords"]), weights(actual["keywords"]))
        else:
            continuity = "n/a (no previous actual)"
        lines.append("     drift: %s   continuity: %s" % (drift, continuity))
        # Chain rule: intent.prev = the previous turn's actual; actual.prev = the
        # same turn's intent. A legacy actual joins its turn with no intent edge.
        if intent and previous_actual and intent["prev"] != previous_actual["own"]:
            lines.append("     [BREAK intent.prev=%s expected previous actual=%s]"
                         % (intent["prev"][:8], previous_actual["own"][:8]))
        # "First turn" is a claim about the CHAIN's start, not about a missing
        # previous actual: a turn whose predecessor emitted no actual must not be
        # accused of starting the chain (measured 2026-10-25 on a live transcript,
        # where every such turn was flagged).
        if intent and not previous_actual and chain and intent is chain[0] and intent["prev"] != ZERO:
            lines.append("     [BREAK intent.prev=%s expected 00000000 (first turn)]" % intent["prev"][:8])
        if actual and intent and actual["prev"] != intent["own"]:
            lines.append("     [BREAK actual.prev=%s expected same-turn intent=%s]"
                         % (actual["prev"][:8], intent["own"][:8]))
        if actual:
            previous_actual = actual
    return lines

def slug_for(path_text: str) -> str:
    """Claude Code's folder name for a project directory.

    Measured under C:/Users/Alexander/.claude/projects (2026-10-17) against
    the `cwd` recorded inside each transcript: every character outside
    [A-Za-z0-9-] becomes '-', one per character, repeats kept
    ('D:' + '\\' -> 'D--'). That covers ':', '\\', '/', '_' (-> '-' in
    D:/zPython/ADID_Python), '.' (-> '-' in .omp and .claude), with '-'
    and alphanumerics preserved and case kept."""
    return re.sub(r"[^A-Za-z0-9-]", "-", path_text)

def project_dir() -> Path:
    """The transcript folder for the current working directory."""
    projects = Path.home() / ".claude" / "projects"
    if not projects.is_dir():
        raise ValueError(f"no transcript root at {projects}")
    # Walk up: transcripts are keyed by the PROJECT root, so running from a
    # subdirectory must still find them. The control that caught this ran the
    # tool from tools/ and got "no folder matches".
    here = Path.cwd().resolve()
    for directory in (here, *here.parents):
        slug = slug_for(str(directory))
        if (projects / slug).is_dir():
            return projects / slug
        candidates = [d for d in projects.iterdir()
                      if d.is_dir() and d.name.lower().endswith(directory.name.lower())]
        if candidates:
            return max(candidates, key=lambda d: sum(f.stat().st_size for f in d.glob("*.jsonl")))
    raise ValueError(f"no folder under {projects} matches {here} or any parent")


def select_session(files: list[Path], needle: str) -> Path:
    """One transcript, or an error naming the count. Never a silent pick: two
    matches mean the caller meant something the selector cannot know."""
    direct = Path(needle)
    if direct.is_file():
        return direct
    matches = [f for f in files if needle in f.name]
    if not matches:
        raise ValueError(f"no session matched {needle!r}")
    if len(matches) > 1:
        raise ValueError(f"{needle!r} matched {len(matches)} sessions; name one")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?", help="session id, file name, or path; default is the newest")
    parser.add_argument("--list", action="store_true", help="list transcripts with their vector counts")
    parser.add_argument("--grep", metavar="TEXT", help="only vectors whose dominant or keywords contain TEXT")
    parser.add_argument("--full", action="store_true", help="print each vector's full block (keywords, dominant, lineage)")
    parser.add_argument("--report", action="store_true",
                        help="per turn: intent/actual ids, drift (intent vs actual) and continuity (actual vs previous actual)")
    args = parser.parse_args()

    folder = project_dir()
    files = sorted(folder.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not files:
        raise ValueError(f"no transcripts in {folder}")

    if args.list:
        print(f"# {folder}")
        for path in files:
            print(f"{len(vectors(path)):>4} vectors  {path.stat().st_size / 1e6:>6.1f} MB  {path.name}")
        return 0

    target = select_session(files, args.session) if args.session else files[-1]
    chain = vectors(target)
    print(f"# {target.name}   {len(chain)} vectors")
    for line in (report(chain) if args.report else format_chain(chain, args.grep, args.full)):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
