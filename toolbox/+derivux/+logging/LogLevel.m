classdef LogLevel < uint8
    %LOGLEVEL Enumeration defining logging verbosity levels
    %   Log levels follow standard conventions with numeric values for
    %   comparison. Higher values = more severe/less verbose.
    %
    %   Example:
    %       level = derivux.logging.LogLevel.INFO;
    %       if level >= derivux.logging.LogLevel.WARN
    %           % This is a warning or error level
    %       end
    %
    %   Levels:
    %       TRACE (5)  - Fine-grained debugging (stream chunks, polling)
    %       DEBUG (10) - Debugging information
    %       INFO  (20) - Normal operational messages
    %       WARN  (30) - Warning conditions
    %       ERROR (40) - Error conditions

    enumeration
        TRACE (5)
        DEBUG (10)
        INFO  (20)
        WARN  (30)
        ERROR (40)
    end

    methods
        function str = tostring(obj)
            %TOSTRING Convert level to string representation
            str = string(obj);
        end
    end

    methods (Static)
        function level = fromString(str)
            %FROMSTRING Parse a string to LogLevel
            %   level = LogLevel.fromString('INFO')
            %   level = LogLevel.fromString('debug')

            arguments
                str {mustBeTextScalar}
            end

            switch upper(str)
                case 'TRACE'
                    level = derivux.logging.LogLevel.TRACE;
                case 'DEBUG'
                    level = derivux.logging.LogLevel.DEBUG;
                case 'INFO'
                    level = derivux.logging.LogLevel.INFO;
                case 'WARN'
                    level = derivux.logging.LogLevel.WARN;
                case 'WARNING'
                    level = derivux.logging.LogLevel.WARN;
                case 'ERROR'
                    level = derivux.logging.LogLevel.ERROR;
                otherwise
                    warning('LogLevel:InvalidLevel', ...
                        'Unknown log level "%s", defaulting to INFO', str);
                    level = derivux.logging.LogLevel.INFO;
            end
        end

        function tf = isValidLevel(str)
            %ISVALIDLEVEL Check if string is a valid log level
            arguments
                str {mustBeTextScalar}
            end

            validLevels = {'TRACE', 'DEBUG', 'INFO', 'WARN', 'WARNING', 'ERROR'};
            tf = ismember(upper(str), validLevels);
        end
    end
end
