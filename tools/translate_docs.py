#!/usr/bin/env python3
"""
Document Translator: Translates Spanish .docx/.pptx/.xlsx/.pdf to English.
Preserves formatting while translating text content.
Uses batched Google Translate for efficiency.
"""

import sys
import os
import time
import re
from pathlib import Path

from deep_translator import GoogleTranslator
from docx import Document as DocxDocument
import pptx
import openpyxl
import fitz  # PyMuPDF

# ---------------------------------------------------------------------------
# Batched translator with delimiter-based grouping
# ---------------------------------------------------------------------------

SEPARATOR = "\n<<<SEP>>>\n"
BATCH_CHARS = 3500

class BatchTranslator:
    def __init__(self):
        self.translator = GoogleTranslator(source="es", target="en")
        self.cache = {}
        self.total = 0
    
    def translate_all(self, texts: list) -> list:
        """Translate a list of texts in batches."""
        results = []
        batch = []
        batch_indices = []
        batch_len = 0
        
        for i, text in enumerate(texts):
            if not text or not text.strip():
                results.append(text)
                continue
            if not any(c in text for c in "áéíóúñüÁÉÍÓÚÑ"):
                # Quick check: if no Spanish accented chars, likely already English
                # Still check for common Spanish words
                if not self._is_spanish(text):
                    results.append(text)
                    continue
            if text in self.cache:
                results.append(self.cache[text])
                continue
            
            batch.append(text)
            batch_indices.append(len(results))
            results.append(None)  # placeholder
            batch_len += len(text) + len(SEPARATOR)
            
            if batch_len >= BATCH_CHARS:
                self._flush_batch(batch, batch_indices, results)
                batch = []
                batch_indices = []
                batch_len = 0
        
        if batch:
            self._flush_batch(batch, batch_indices, results)
        
        return results
    
    def _flush_batch(self, batch, indices, results):
        batch_text = SEPARATOR.join(batch)
        print(f"    Translating batch: {len(batch)} texts, {len(batch_text)} chars...")
        self.total += len(batch)
        
        try:
            translated = self.translator.translate(batch_text)
            parts = translated.split(SEPARATOR)
            # Sometimes the translator mangles the separator
            if len(parts) != len(batch):
                # Fall back to individual translation
                for j, text in enumerate(batch):
                    try:
                        results[indices[j]] = self.translator.translate(text)
                        time.sleep(0.3)
                    except Exception:
                        results[indices[j]] = text
            else:
                for j, part in enumerate(parts):
                    self.cache[batch[j]] = part.strip()
                    results[indices[j]] = self.cache[batch[j]]
        except Exception as e:
            print(f"    [WARN] Batch failed: {e}, falling back to individual...")
            for j, text in enumerate(batch):
                try:
                    results[indices[j]] = self.translator.translate(text)
                    time.sleep(0.3)
                except Exception:
                    results[indices[j]] = text
        time.sleep(1.0)
    
    def _is_spanish(self, text: str) -> bool:
        """Quick heuristic to check if text is Spanish."""
        spanish_words = {"el", "la", "los", "las", "un", "una", "de", "del", "en",
                         "para", "por", "con", "sin", "y", "o", "que", "como",
                         "este", "esta", "es", "son", "fue", "fueron", "tiene",
                         "tienen", "puede", "pueden", "debe", "deben", "muy",
                         "más", "pero", "también", "cuando", "donde", "porque",
                         "si", "no", "sí", "ya", "solo", "todo", "cada", "otro",
                         "desde", "hasta", "entre", "sobre", "durante", "según"}
        words = set(text.lower().split())
        return bool(words & spanish_words)


# ---------------------------------------------------------------------------
# .docx handler (batched)
# ---------------------------------------------------------------------------

def translate_docx(input_path: str, output_path: str, bt: BatchTranslator):
    print(f"  [DOCX] {os.path.basename(input_path)}")
    doc = DocxDocument(input_path)
    
    # Collect all translatable runs
    targets = []  # (run, original_text)
    
    def collect(paragraphs):
        for para in paragraphs:
            for run in para.runs:
                if run.text and run.text.strip():
                    targets.append(run)
    
    collect(doc.paragraphs)
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                collect(cell.paragraphs)
    for section in doc.sections:
        for item in [section.header, section.first_page_header,
                      section.even_page_header, section.footer,
                      section.first_page_footer, section.even_page_footer]:
            if item:
                collect(item.paragraphs)
    
    # Batch translate
    texts = [t.text for t in targets]
    print(f"    {len(texts)} text runs collected")
    translated = bt.translate_all(texts)
    
    # Apply translations
    for run, new_text in zip(targets, translated):
        run.text = new_text
    
    doc.save(output_path)
    print(f"    Saved -> {os.path.basename(output_path)}")


# ---------------------------------------------------------------------------
# .pptx handler (batched)
# ---------------------------------------------------------------------------

def translate_pptx(input_path: str, output_path: str, bt: BatchTranslator):
    print(f"  [PPTX] {os.path.basename(input_path)}")
    prs = pptx.Presentation(input_path)
    
    targets = []
    
    for slide in prs.slides:
        for shape in slide.shapes:
            if shape.has_text_frame:
                for para in shape.text_frame.paragraphs:
                    for run in para.runs:
                        if run.text and run.text.strip():
                            targets.append(run)
            if shape.has_table:
                for row in shape.table.rows:
                    for cell in row.cells:
                        if cell.text_frame:
                            for para in cell.text_frame.paragraphs:
                                for run in para.runs:
                                    if run.text and run.text.strip():
                                        targets.append(run)
    
    texts = [t.text for t in targets]
    print(f"    {len(texts)} text runs collected")
    translated = bt.translate_all(texts)
    
    for run, new_text in zip(targets, translated):
        run.text = new_text
    
    prs.save(output_path)
    print(f"    Saved -> {os.path.basename(output_path)}")


# ---------------------------------------------------------------------------
# .xlsx handler (batched)
# ---------------------------------------------------------------------------

def translate_xlsx(input_path: str, output_path: str, bt: BatchTranslator):
    print(f"  [XLSX] {os.path.basename(input_path)}")
    wb = openpyxl.load_workbook(input_path)
    
    targets = []
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        for row in ws.iter_rows():
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.strip():
                    targets.append(cell)
    
    texts = [t.value for t in targets]
    print(f"    {len(texts)} cells collected")
    translated = bt.translate_all(texts)
    
    for cell, new_text in zip(targets, translated):
        cell.value = new_text
    
    wb.save(output_path)
    print(f"    Saved -> {os.path.basename(output_path)}")


# ---------------------------------------------------------------------------
# .pdf handler (via PyMuPDF)
# ---------------------------------------------------------------------------

def translate_pdf(input_path: str, output_path: str, bt: BatchTranslator):
    print(f"  [PDF] {os.path.basename(input_path)}")
    doc = fitz.open(input_path)
    
    all_blocks = []
    for page_num in range(len(doc)):
        page = doc[page_num]
        for block in page.get_text("blocks"):
            if block[6] == 0 and block[4].strip():  # text block
                all_blocks.append((page_num, block))
    
    texts = [b[1][4].strip() for b in all_blocks]
    print(f"    {len(texts)} text blocks collected")
    translated = bt.translate_all(texts)
    
    for (page_num, block), new_text in zip(all_blocks, translated):
        page = doc[page_num]
        x0, y0, x1, y1 = block[:4]
        if new_text == block[4].strip():
            continue
        try:
            page.add_redact_annot(fitz.Rect(x0, y0, x1, y1 + 5))
            page.apply_redactions()
            rect = fitz.Rect(x0, y0, x1, y1 + 20)
            page.insert_textbox(rect, new_text, fontsize=10, fontname="helv", color=(0,0,0))
        except Exception:
            pass
    
    doc.save(output_path)
    doc.close()
    print(f"    Saved -> {os.path.basename(output_path)}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Translate Spanish documents to English")
    parser.add_argument("input", help="Input file path")
    parser.add_argument("--output", "-o", help="Output file path (default: *_EN.<ext>)")
    parser.add_argument("--mode", "-m", choices=["docx", "pptx", "xlsx", "pdf", "auto"],
                        default="auto", help="File type (default: auto-detect)")
    args = parser.parse_args()
    
    if not os.path.exists(args.input):
        print(f"ERROR: File not found: {args.input}")
        return 1
    
    ext = Path(args.input).suffix.lower()
    mode = args.mode if args.mode != "auto" else ext.lstrip(".")
    
    if not args.output:
        p = Path(args.input)
        args.output = str(p.parent / f"{p.stem}_EN{p.suffix}")
    
    print(f"\n{'='*60}")
    print(f"Translating: {args.input}")
    print(f"      -> EN: {args.output}")
    print(f"      Mode: {mode}")
    print(f"{'='*60}\n")
    
    bt = BatchTranslator()
    
    handlers = {
        "docx": translate_docx,
        "pptx": translate_pptx,
        "xlsx": translate_xlsx,
        "pdf": translate_pdf,
    }
    
    if mode not in handlers:
        print(f"ERROR: Unsupported format: {mode}")
        return 1
    
    handlers[mode](args.input, args.output, bt)
    
    print(f"\n  Done! Total texts translated: {bt.total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
