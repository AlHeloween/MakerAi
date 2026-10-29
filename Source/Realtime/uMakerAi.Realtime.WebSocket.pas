// MakerAI Suite — Realtime.WebSocket compatibility shim
// Redirects legacy types to new TAiWSClient (Source/WebSocket/)
//
// The actual implementation is in:
//   uMakerAi.WebSocket.Client   — TAiWSClient, ITlsTransport, TAiWSReaderThread
//   uMakerAi.WebSocket.SChannel — TSChannelTransport (Windows, secur32.dll)
//   uMakerAi.WebSocket.OpenSSL  — TOpenSSLTransport  (POSIX, libssl dlopen)

unit uMakerAi.Realtime.WebSocket;

interface

uses
  uMakerAi.WebSocket.Client;

const
  WS_DIAG_LOG = '';  // activate with 'C:\Temp\wsclient_diag.txt' for debug

type
  TAiRealtimeWSOpcode       = TAiWSOpcode;
  TAiRealtimeWSFrameEvent   = TAiWSFrameEvent;
  TAiRealtimeWSErrorEvent   = TAiWSErrorEvent;
  TAiRealtimeWSClient       = TAiWSClient;
  TAiRealtimeWSReaderThread = TAiWSReaderThread;

implementation

end.
