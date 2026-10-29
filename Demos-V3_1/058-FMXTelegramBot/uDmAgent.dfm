object DmAgent: TDmAgent
  Height = 480
  Width = 640
  object AiPrompts1: TAiPrompts
    Items = <
      item
        Nombre = 'SYS_PROMPT'
        Strings.Strings = (
          'You are a powerful AI assistant accessible via Telegram.'
          'Herramientas disponibles:'
          'SISTEMA : shell_exec, file_read, file_write, file_list'
          
            'MEMORIA : memory_save, memory_get, memory_delete, memory_list, m' +
            'emory_search'
          'AGENTS : agent_run (type: "analyze" or "code_review")'
          
            'VOICE     : tg_voice (voice synthesis '#8212' sends an audio to the ' +
            'Telegram chat)'
          
            'PPM     : ppm_install (installs any external capability from' +
            ' the PPM registry)'
          
            'Key rule: if you need a tool that is not in the' +
            ' list (weather, database,'
          
            'GitHub, email, translation, etc.), first call ppm_install{"' +
            'capability":"keyword"}.'
          
            'After installation, the new tools are available ' +
            'immediately.'
          'Other rules: be concise, use plain text (without markdown),'
          
            'use the tools proactively when the user asks to do something in the ' +
            'to do something in the system'
          'or wants to remember information.'
          'Ask for confirmation before destructive operations.'
          'Always respond in Spanish.)')
      end>
    PPMRegistryUrl = 'https://registry.cimamaker.com'
    Left = 456
    Top = 224
  end
  object AiConn: TAiChatConnection
    AiFunctions = AiFunctions1
    Completion_tokens = 0
    Left = 136
    Top = 232
  end
  object AiFunctions1: TAiFunctions
    Functions = <
      item
        FunctionName = 'ppm_install'
        OnAction = AiFunctions1Functions0ppm_installAction
        Description.Strings = (
          
            '    Search and auto-install an external capability from the PPM ' +
            'registry'
          
            '    (118+ MCP tools: weather, GitHub, databases, email, translat' +
            'ion, finance,'
          
            '    Kubernetes, Kafka, S3, Telegram, Discord, Shopify, and more)' +
            '.'
          
            '    Call this when you need a tool that is not currently availab' +
            'le.'
          '    After installation the new tools are immediately callable.')
        Parameters = <
          item
            Name = 'capability'
            ParamType = ptString
            Description.Strings = (
              'Keyword or package name describing the needed capability'
              
                '     (e.g. "weather", "github", "postgres", "email", "translate"' +
                ', "coingecko")')
            Required = True
          end>
        Default = False
        Tag = 0
        ToolType = tt_function
      end>
    MCPClients = <>
    PPMRegistryUrl = 'https://registry.cimamaker.com'
    Left = 296
    Top = 184
  end
end
