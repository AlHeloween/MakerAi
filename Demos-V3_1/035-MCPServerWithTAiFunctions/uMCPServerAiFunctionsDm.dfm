object MCPServerAiFunctionsDm: TMCPServerAiFunctionsDm
  OnCreate = DataModuleCreate
  Height = 480
  Width = 640
  object AiFunctions1: TAiFunctions
    Functions = <
      item
        FunctionName = 'GetFechaHora'
        OnAction = AiFunctions1Functions0GetFechaHoraAction
        Description.Strings = (
          'Gets the date and time of a given city  COUNTRY,CITY')
        Parameters = <
          item
            Name = 'Ciudad'
            ParamType = ptString
            Description.Strings = (
              'The city whose date and time you want to know')
            Required = True
          end>
        Default = False
        Tag = 0
        ToolType = tt_function
      end>
    MCPClients = <
      item
        Connected = False
        Enabled = True
        Name = 'MCPClient'
        TransportType = tpStdIo
        Params.Strings = (
          'Command=C:\mcp\servers\McpFileServerStIO.exe'
          'Timeout=15000')
        Configuration = '(Properties, Click [...] to edit)'
      end>
    Left = 344
    Top = 200
  end
  object AiMCPServer1: TAiMCPStdioServer
    ServerName = 'Delphi-DataModule-Server StdIO'
    AiFunctions = AiFunctions1
    Left = 152
    Top = 88
  end
  object AiMCPHttpServer1: TAiMCPHttpServer
    ServerName = 'Delphi-DataModule-Server HTTP'
    AiFunctions = AiFunctions1
    Port = 3000
    CorsEnabled = True
    CorsAllowedOrigins = '*'
    Left = 384
    Top = 88
  end
end
