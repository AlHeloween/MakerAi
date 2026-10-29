object FMCPServerFileSystem_Tool: TFMCPServerFileSystem_Tool
  Height = 480
  Width = 640
  object AiMCPStdioServer1: TAiMCPStdioServer
    ServerName = 'FileSystem'
    AiFunctions = AiFunctions1
    Left = 160
    Top = 104
  end
  object AiFunctions1: TAiFunctions
    Functions = <
      item
        FunctionName = 'fs_listar'
        OnAction = AiFunctions1Functions0fs_listarAction
        Description.Strings = (
          
            'Lists the directory to which it has access; it is a single' +
            ' sandbox directory.')
        Parameters = <
          item
            Name = 'filtro'
            ParamType = ptString
            Description.Strings = (
              'Search filter for files')
            Required = True
          end>
        Default = False
        Tag = 0
        ToolType = tt_function
      end>
    MCPClients = <>
    Left = 304
    Top = 168
  end
end
