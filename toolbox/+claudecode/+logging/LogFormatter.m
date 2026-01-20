classdef LogFormatter
    %LOGFORMATTER Utility class for formatting log entries as JSON
    %   Provides static methods for converting log data to JSON-lines format
    %   suitable for machine parsing and behavioral reconstruction.
    %
    %   Example:
    %       entry = struct('level', 'INFO', 'event', 'test');
    %       jsonStr = claudecode.logging.LogFormatter.toJson(entry);
    %
    %   See also: Logger, LogConfig

    methods (Static)
        function jsonStr = toJson(data)
            %TOJSON Convert data structure to JSON string
            %   Handles MATLAB-specific types and ensures proper encoding.
            %
            %   Input:
            %       data - struct, cell, or scalar value
            %
            %   Output:
            %       jsonStr - JSON string representation

            arguments
                data
            end

            try
                % Use MATLAB's built-in JSON encoder
                jsonStr = jsonencode(data);
            catch ME
                % Fallback for problematic data
                jsonStr = claudecode.logging.LogFormatter.manualEncode(data);
            end
        end

        function entry = createEntry(level, component, event, data, options)
            %CREATEENTRY Create a standardized log entry structure
            %
            %   Input:
            %       level     - LogLevel or string
            %       component - Source component name (e.g., 'ChatUIController')
            %       event     - Event name (e.g., 'message_received')
            %       data      - Event-specific data structure
            %       options   - Name-value pairs for additional fields
            %
            %   Options:
            %       SessionId   - Session identifier for correlation
            %       DurationMs  - Operation duration in milliseconds
            %       TraceId     - Trace identifier for related events
            %       StackTrace  - Stack trace string
            %
            %   Output:
            %       entry - Struct ready for JSON encoding

            arguments
                level
                component (1,1) string
                event (1,1) string
                data = struct()
                options.SessionId (1,1) string = ""
                options.DurationMs double = []
                options.TraceId (1,1) string = ""
                options.StackTrace (1,1) string = ""
            end

            % Convert level to string if needed
            if isa(level, 'claudecode.logging.LogLevel')
                levelStr = string(level);
            else
                levelStr = upper(string(level));
            end

            % Build entry structure
            entry = struct();
            entry.ts = claudecode.logging.LogFormatter.isoTimestamp();
            entry.level = levelStr;

            if options.SessionId ~= ""
                entry.session_id = options.SessionId;
            end

            entry.component = component;
            entry.event = event;

            % Add data if not empty
            if ~isempty(data) && ~(isstruct(data) && isempty(fieldnames(data)))
                entry.data = claudecode.logging.LogFormatter.sanitizeData(data);
            end

            % Add optional fields
            if ~isempty(options.DurationMs)
                entry.duration_ms = options.DurationMs;
            end

            if options.TraceId ~= ""
                entry.trace_id = options.TraceId;
            end

            if options.StackTrace ~= ""
                entry.stack_trace = options.StackTrace;
            end
        end

        function ts = isoTimestamp()
            %ISOTIMESTAMP Get current time in ISO 8601 format with microseconds
            %   Returns: '2026-01-20T15:30:45.123456Z'

            now = datetime('now', 'TimeZone', 'UTC');
            ts = char(now, 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''');
        end

        function sanitized = sanitizeData(data)
            %SANITIZEDATA Clean data for JSON encoding
            %   Handles special MATLAB types that don't encode well.

            arguments
                data
            end

            if isstruct(data)
                sanitized = struct();
                fields = fieldnames(data);
                for i = 1:numel(fields)
                    fieldName = fields{i};
                    fieldValue = data.(fieldName);
                    sanitized.(fieldName) = claudecode.logging.LogFormatter.sanitizeValue(fieldValue);
                end
            elseif iscell(data)
                sanitized = cellfun(@claudecode.logging.LogFormatter.sanitizeValue, ...
                    data, 'UniformOutput', false);
            else
                sanitized = claudecode.logging.LogFormatter.sanitizeValue(data);
            end
        end

        function val = sanitizeValue(value)
            %SANITIZEVALUE Clean individual value for JSON encoding

            if isempty(value)
                val = [];
            elseif ischar(value) || isstring(value)
                val = string(value);
            elseif isnumeric(value)
                if isnan(value)
                    val = "NaN";
                elseif isinf(value)
                    val = "Inf";
                else
                    val = value;
                end
            elseif islogical(value)
                val = value;
            elseif isdatetime(value)
                val = char(value, 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''');
            elseif isduration(value)
                val = milliseconds(value);
            elseif isstruct(value)
                val = claudecode.logging.LogFormatter.sanitizeData(value);
            elseif iscell(value)
                val = cellfun(@claudecode.logging.LogFormatter.sanitizeValue, ...
                    value, 'UniformOutput', false);
            elseif isa(value, 'MException')
                val = struct('identifier', value.identifier, ...
                             'message', value.message);
            elseif isobject(value)
                % Try to convert objects to struct
                try
                    val = struct(value);
                    val = claudecode.logging.LogFormatter.sanitizeData(val);
                catch
                    val = class(value);
                end
            else
                % Last resort: convert to string
                try
                    val = string(value);
                catch
                    val = class(value);
                end
            end
        end

        function truncated = truncateString(str, maxLength)
            %TRUNCATESTRING Truncate string to maximum length
            %   Adds '...[truncated]' suffix if truncated.

            arguments
                str (1,1) string
                maxLength (1,1) double = 10000
            end

            if strlength(str) > maxLength
                truncated = extractBefore(str, maxLength - 14) + "...[truncated]";
            else
                truncated = str;
            end
        end
    end

    methods (Static, Access = private)
        function jsonStr = manualEncode(data)
            %MANUALENCODE Fallback JSON encoder for problematic data

            if ischar(data) || isstring(data)
                % Escape special characters
                str = char(data);
                str = strrep(str, '\', '\\');
                str = strrep(str, '"', '\"');
                str = strrep(str, newline, '\n');
                str = strrep(str, char(13), '\r');
                str = strrep(str, char(9), '\t');
                jsonStr = sprintf('"%s"', str);
            elseif isnumeric(data) && isscalar(data)
                if isnan(data)
                    jsonStr = '"NaN"';
                elseif isinf(data)
                    jsonStr = '"Inf"';
                else
                    jsonStr = num2str(data);
                end
            elseif islogical(data) && isscalar(data)
                if data
                    jsonStr = 'true';
                else
                    jsonStr = 'false';
                end
            elseif isstruct(data) && isscalar(data)
                fields = fieldnames(data);
                parts = cell(1, numel(fields));
                for i = 1:numel(fields)
                    key = fields{i};
                    val = claudecode.logging.LogFormatter.manualEncode(data.(key));
                    parts{i} = sprintf('"%s":%s', key, val);
                end
                jsonStr = sprintf('{%s}', strjoin(parts, ','));
            elseif iscell(data)
                parts = cellfun(@claudecode.logging.LogFormatter.manualEncode, ...
                    data, 'UniformOutput', false);
                jsonStr = sprintf('[%s]', strjoin(parts, ','));
            elseif isempty(data)
                jsonStr = 'null';
            else
                % Fallback to type name
                jsonStr = sprintf('"%s"', class(data));
            end
        end
    end
end
