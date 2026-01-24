classdef CredentialStore < handle
    %CREDENTIALSTORE Secure credential storage using AES encryption
    %
    %   This class provides encrypted storage for API keys using Java's
    %   javax.crypto.Cipher with AES encryption. Credentials are stored in
    %   MATLAB preferences (not in JSON settings file).
    %
    %   The encryption key is derived from machine-specific data (hostname,
    %   username, prefdir) to tie credentials to the specific machine.
    %
    %   Example:
    %       store = derivux.config.CredentialStore();
    %       store.setApiKey('sk-ant-api03-...');
    %       key = store.getApiKey();  % Returns decrypted key
    %       store.clearApiKey();
    %
    %   Security Notes:
    %       - API key is never written to JSON settings file
    %       - Environment variable ANTHROPIC_API_KEY takes precedence
    %       - Encryption is tied to the specific machine

    properties (Constant, Access = private)
        PREF_GROUP = 'Derivux'
        PREF_API_KEY = 'encryptedApiKey'
        PREF_AUTH_METHOD = 'authMethod'
        CIPHER_ALGORITHM = 'AES'
        KEY_SIZE = 128  % bits
    end

    methods (Static)
        function setApiKey(apiKey)
            %SETAPIKEY Encrypt and store API key
            %
            %   CredentialStore.setApiKey(key) encrypts the key and stores
            %   it in MATLAB preferences.

            if isempty(apiKey)
                derivux.config.CredentialStore.clearApiKey();
                return;
            end

            % Validate API key format (basic check)
            apiKey = char(apiKey);
            if ~startsWith(apiKey, 'sk-')
                warning('CredentialStore:InvalidFormat', ...
                    'API key should start with "sk-". Storing anyway.');
            end

            try
                % Encrypt the key
                encryptedBytes = derivux.config.CredentialStore.encrypt(apiKey);

                % Convert to base64 for storage
                encoder = java.util.Base64.getEncoder();
                base64Str = char(encoder.encodeToString(encryptedBytes));

                % Store in preferences
                setpref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_API_KEY, base64Str);

            catch ME
                error('CredentialStore:EncryptionError', ...
                    'Failed to encrypt API key: %s', ME.message);
            end
        end

        function apiKey = getApiKey()
            %GETAPIKEY Decrypt and retrieve API key
            %
            %   key = CredentialStore.getApiKey() returns the decrypted API
            %   key. Returns empty string if no key is stored.
            %
            %   Environment variable ANTHROPIC_API_KEY takes precedence.

            apiKey = '';

            % Check environment variable first (takes precedence)
            envKey = getenv('ANTHROPIC_API_KEY');
            if ~isempty(envKey)
                apiKey = envKey;
                return;
            end

            % Check if key exists in preferences
            if ~derivux.config.CredentialStore.hasApiKey()
                return;
            end

            try
                % Get encrypted key from preferences
                base64Str = getpref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_API_KEY);

                % Decode from base64
                decoder = java.util.Base64.getDecoder();
                encryptedBytes = decoder.decode(base64Str);

                % Decrypt
                apiKey = derivux.config.CredentialStore.decrypt(encryptedBytes);

            catch ME
                warning('CredentialStore:DecryptionError', ...
                    'Failed to decrypt API key: %s. Clearing stored key.', ME.message);
                derivux.config.CredentialStore.clearApiKey();
                apiKey = '';
            end
        end

        function clearApiKey()
            %CLEARAPIKEY Remove stored API key
            %
            %   CredentialStore.clearApiKey() removes the encrypted API key
            %   from MATLAB preferences.

            if ispref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_API_KEY)
                rmpref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_API_KEY);
            end
        end

        function exists = hasApiKey()
            %HASAPIKEY Check if API key is stored or available via env var
            %
            %   exists = CredentialStore.hasApiKey() returns true if an API
            %   key is available (either stored or via environment variable).

            % Check environment variable first
            envKey = getenv('ANTHROPIC_API_KEY');
            if ~isempty(envKey)
                exists = true;
                return;
            end

            % Check preferences
            exists = ispref(derivux.config.CredentialStore.PREF_GROUP, ...
                derivux.config.CredentialStore.PREF_API_KEY);
        end

        function setAuthMethod(method)
            %SETAUTHMETHOD Store authentication method preference
            %
            %   CredentialStore.setAuthMethod(method) stores the preferred
            %   authentication method ('subscription' or 'api_key').

            method = char(method);
            if ~ismember(method, {'subscription', 'api_key'})
                error('CredentialStore:InvalidMethod', ...
                    'Auth method must be "subscription" or "api_key"');
            end

            setpref(derivux.config.CredentialStore.PREF_GROUP, ...
                derivux.config.CredentialStore.PREF_AUTH_METHOD, method);
        end

        function method = getAuthMethod()
            %GETAUTHMETHOD Get stored authentication method preference
            %
            %   method = CredentialStore.getAuthMethod() returns the stored
            %   authentication method. Defaults to 'subscription'.

            if ispref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_AUTH_METHOD)
                method = getpref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_AUTH_METHOD);
            else
                method = 'subscription';  % Default
            end
        end

        function valid = validateApiKey(apiKey)
            %VALIDATEAPIKEY Check if API key has valid format
            %
            %   valid = CredentialStore.validateApiKey(key) returns true if
            %   the key has valid Anthropic API key format.

            apiKey = char(apiKey);

            % Basic format validation
            % Anthropic keys start with 'sk-ant-' and are 100+ chars
            valid = startsWith(apiKey, 'sk-ant-') && length(apiKey) >= 100;
        end

        function info = getAuthInfo()
            %GETAUTHINFO Get comprehensive authentication status
            %
            %   info = CredentialStore.getAuthInfo() returns a struct with:
            %       - authMethod: 'subscription' or 'api_key'
            %       - hasApiKey: true if API key is available
            %       - apiKeySource: 'stored', 'env', or 'none'
            %       - apiKeyMasked: Masked version of key (last 4 chars)

            info = struct();
            info.authMethod = derivux.config.CredentialStore.getAuthMethod();
            info.hasApiKey = derivux.config.CredentialStore.hasApiKey();

            % Determine API key source
            envKey = getenv('ANTHROPIC_API_KEY');
            if ~isempty(envKey)
                info.apiKeySource = 'env';
                info.apiKeyMasked = derivux.config.CredentialStore.maskApiKey(envKey);
            elseif ispref(derivux.config.CredentialStore.PREF_GROUP, ...
                    derivux.config.CredentialStore.PREF_API_KEY)
                info.apiKeySource = 'stored';
                key = derivux.config.CredentialStore.getApiKey();
                info.apiKeyMasked = derivux.config.CredentialStore.maskApiKey(key);
            else
                info.apiKeySource = 'none';
                info.apiKeyMasked = '';
            end
        end
    end

    methods (Static, Access = private)
        function encryptedBytes = encrypt(plainText)
            %ENCRYPT Encrypt plaintext using AES

            % Get encryption key
            secretKey = derivux.config.CredentialStore.getSecretKey();

            % Create cipher
            cipher = javax.crypto.Cipher.getInstance('AES');
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, secretKey);

            % Encrypt
            plainBytes = uint8(plainText);
            encryptedBytes = cipher.doFinal(plainBytes);
        end

        function plainText = decrypt(encryptedBytes)
            %DECRYPT Decrypt ciphertext using AES

            % Get encryption key
            secretKey = derivux.config.CredentialStore.getSecretKey();

            % Create cipher
            cipher = javax.crypto.Cipher.getInstance('AES');
            cipher.init(javax.crypto.Cipher.DECRYPT_MODE, secretKey);

            % Decrypt
            decryptedBytes = cipher.doFinal(encryptedBytes);
            plainText = char(decryptedBytes');
        end

        function secretKey = getSecretKey()
            %GETSECRETKEY Derive encryption key from machine-specific data
            %
            %   The key is derived from:
            %   - Hostname
            %   - Username
            %   - MATLAB prefdir path
            %
            %   This ties the encrypted credentials to the specific machine.

            % Gather machine-specific data
            try
                hostname = char(java.net.InetAddress.getLocalHost().getHostName());
            catch
                hostname = 'unknown-host';
            end

            username = char(java.lang.System.getProperty('user.name'));
            prefdirPath = prefdir;

            % Combine into seed string
            seedString = [hostname, ':', username, ':', prefdirPath];

            % Hash to get consistent key material
            md = java.security.MessageDigest.getInstance('SHA-256');
            hashBytes = md.digest(uint8(seedString));

            % Use first 16 bytes (128 bits) for AES key
            keyBytes = hashBytes(1:16);

            % Create SecretKeySpec
            secretKey = javax.crypto.spec.SecretKeySpec(keyBytes, 'AES');
        end

        function masked = maskApiKey(apiKey)
            %MASKAPIKEY Create masked version of API key for display
            %
            %   Shows prefix and last 4 characters: sk-ant-api03-****1234

            apiKey = char(apiKey);
            if isempty(apiKey)
                masked = '';
                return;
            end

            if length(apiKey) > 20
                prefix = apiKey(1:min(13, length(apiKey)));  % 'sk-ant-api03-'
                suffix = apiKey(end-3:end);  % Last 4 chars
                masked = [prefix, '****', suffix];
            else
                masked = '****';
            end
        end
    end
end
