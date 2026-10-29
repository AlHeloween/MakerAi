unit uMakerAi.Utils.PcmToWav;

interface

uses
  System.SysUtils, System.Classes;

type
  // WAV header structure
  TWAVHeader = packed record
    // RIFF chunk
    ChunkID: array [0 .. 3] of AnsiChar; // "RIFF"
    ChunkSize: Cardinal; // File size - 8 bytes
    Format: array [0 .. 3] of AnsiChar; // "WAVE"

    // fmt subchunk
    Subchunk1ID: array [0 .. 3] of AnsiChar; // "fmt "
    Subchunk1Size: Cardinal; // 16 for PCM
    AudioFormat: Word; // 1 for PCM
    NumChannels: Word; // Number of channels
    SampleRate: Cardinal; // Sample rate
    ByteRate: Cardinal; // SampleRate * NumChannels * BitsPerSample/8
    BlockAlign: Word; // NumChannels * BitsPerSample/8
    BitsPerSample: Word; // Bits per sample

    // data subchunk
    Subchunk2ID: array [0 .. 3] of AnsiChar; // "data"
    Subchunk2Size: Cardinal; // PCM data size
  end;

  // Main function to convert PCM to WAV
function ConvertPCMToWAV(const PCMFilePath, WAVFilePath: string; SampleRate: Cardinal = 44100; Channels: Word = 2;
  BitsPerSample: Word = 16): Boolean;

// Function to convert PCM to WAV from TMemoryStream
function ConvertPCMStreamToWAVStream(const PCMStream: TMemoryStream; out WAVStream: TMemoryStream; SampleRate: Cardinal = 44100;
  Channels: Word = 2; BitsPerSample: Word = 16): Boolean;

implementation

function ConvertPCMToWAV(const PCMFilePath, WAVFilePath: string; SampleRate: Cardinal; Channels: Word; BitsPerSample: Word): Boolean;
var
  PCMFile, WAVFile: TFileStream;
  Header: TWAVHeader;
  PCMSize: Cardinal;
  Buffer: array [0 .. 4095] of Byte;
  BytesRead: Integer;
begin
  //Result := False;

  try
    // Verify that the PCM file exists
    if not FileExists(PCMFilePath) then
    begin
      raise Exception.Create('The PCM file does not exist: ' + PCMFilePath);
    end;

    // Open PCM file
    PCMFile := TFileStream.Create(PCMFilePath, fmOpenRead);
    try
      // Get PCM file size
      PCMSize := PCMFile.Size;

      // Create WAV file
      WAVFile := TFileStream.Create(WAVFilePath, fmCreate);
      try
        // Configure WAV header
        FillChar(Header, SizeOf(Header), 0);

        // RIFF chunk
        Header.ChunkID := 'RIFF';
        Header.ChunkSize := 36 + PCMSize;
        Header.Format := 'WAVE';

        // fmt subchunk
        Header.Subchunk1ID := 'fmt ';
        Header.Subchunk1Size := 16;
        Header.AudioFormat := 1; // PCM
        Header.NumChannels := Channels;
        Header.SampleRate := SampleRate;
        Header.ByteRate := SampleRate * Channels * (BitsPerSample div 8);
        Header.BlockAlign := Channels * (BitsPerSample div 8);
        Header.BitsPerSample := BitsPerSample;

        // data subchunk
        Header.Subchunk2ID := 'data';
        Header.Subchunk2Size := PCMSize;

        // Write WAV header
        WAVFile.WriteBuffer(Header, SizeOf(Header));

        // Copy PCM data to WAV file
        PCMFile.Position := 0;
        while PCMFile.Position < PCMFile.Size do
        begin
          BytesRead := PCMFile.Read(Buffer, SizeOf(Buffer));
          if BytesRead > 0 then
            WAVFile.WriteBuffer(Buffer, BytesRead);
        end;

        Result := True;

      finally
        WAVFile.Free;
      end;

    finally
      PCMFile.Free;
    end;

  except
    on E: Exception do
    begin
      // If there is an error and the WAV file was partially created, delete it
      if FileExists(WAVFilePath) then
        DeleteFile(WAVFilePath);
      raise;
    end;
  end;
end;

// Function to convert PCM to WAV from TMemoryStream
function ConvertPCMStreamToWAVStream(const PCMStream: TMemoryStream; out WAVStream: TMemoryStream; SampleRate: Cardinal = 44100;
  Channels: Word = 2; BitsPerSample: Word = 16): Boolean;
var
  Header: TWAVHeader;
  PCMSize: Cardinal;
  Buffer: array [0 .. 4095] of Byte;
  BytesRead: Integer;
begin
  //Result := False;
  WAVStream := nil; // Initialize WAVStream

  try
    // Create the output WAV stream
    WAVStream := TMemoryStream.Create;
    try
      // Get the PCM stream size
      PCMSize := PCMStream.Size;

      // Configure the WAV header
      FillChar(Header, SizeOf(Header), 0);

      // RIFF chunk
      Header.ChunkID := 'RIFF';
      Header.ChunkSize := 36 + PCMSize;
      Header.Format := 'WAVE';

      // fmt subchunk
      Header.Subchunk1ID := 'fmt ';
      Header.Subchunk1Size := 16;
      Header.AudioFormat := 1; // PCM
      Header.NumChannels := Channels;
      Header.SampleRate := SampleRate;
      Header.ByteRate := SampleRate * Channels * (BitsPerSample div 8);
      Header.BlockAlign := Channels * (BitsPerSample div 8);
      Header.BitsPerSample := BitsPerSample;

      // data subchunk
      Header.Subchunk2ID := 'data';
      Header.Subchunk2Size := PCMSize;

      // Write the WAV header to the output stream
      WAVStream.WriteBuffer(Header, SizeOf(Header));

      // Copy the PCM data to the WAV stream
      PCMStream.Position := 0;
      while PCMStream.Position < PCMStream.Size do
      begin
        BytesRead := PCMStream.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
          WAVStream.WriteBuffer(Buffer, BytesRead);
      end;

      // Reset the WAV stream position to 0 for subsequent reading
      WAVStream.Position := 0;

      Result := True;

    except
      on E: Exception do
      begin
        // If there is an error, free the WAV stream and propagate the exception
        WAVStream.Free;
        WAVStream := nil;
        raise;
      end;
    end;

  except
    on E: Exception do
    begin
      if Assigned(WAVStream) then
        WAVStream.Free;
      WAVStream := nil;
      raise;
    end;
  end;
end;

end.
