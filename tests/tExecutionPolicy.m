classdef tExecutionPolicy < matlab.unittest.TestCase
    %TEXECUTIONPOLICY Unit tests for ExecutionPolicy enumeration
    %
    %   Run tests with:
    %       results = runtests('tExecutionPolicy');

    properties (TestParameter)
        % All enum values for parameterized tests
        EnumValues = struct(...
            'Auto', derivux.config.ExecutionPolicy.Auto, ...
            'Prompt', derivux.config.ExecutionPolicy.Prompt, ...
            'Disabled', derivux.config.ExecutionPolicy.Disabled)
    end

    methods (Test)
        %% Enumeration Existence Tests
        function testAutoEnumExists(testCase)
            %TESTAUTOENUMEXISTS Verify Auto enum value exists

            policy = derivux.config.ExecutionPolicy.Auto;
            testCase.verifyClass(policy, 'derivux.config.ExecutionPolicy');
        end

        function testPromptEnumExists(testCase)
            %TESTPROMPTENUMEXISTS Verify Prompt enum value exists

            policy = derivux.config.ExecutionPolicy.Prompt;
            testCase.verifyClass(policy, 'derivux.config.ExecutionPolicy');
        end

        function testDisabledEnumExists(testCase)
            %TESTDISABLEDENUMEXISTS Verify Disabled enum value exists

            policy = derivux.config.ExecutionPolicy.Disabled;
            testCase.verifyClass(policy, 'derivux.config.ExecutionPolicy');
        end

        function testExactlyThreeEnumValues(testCase)
            %TESTEXACTLYTHREEENUMVALUES Verify only three enum values exist

            mc = ?derivux.config.ExecutionPolicy;
            enumList = mc.EnumerationMemberList;

            testCase.verifyLength(enumList, 3);
        end

        %% requiresApproval Method Tests
        function testAutoDoesNotRequireApproval(testCase)
            %TESTAUTODOESNOTREQUIREAPPROVAL Verify Auto returns false

            policy = derivux.config.ExecutionPolicy.Auto;
            testCase.verifyFalse(policy.requiresApproval());
        end

        function testPromptRequiresApproval(testCase)
            %TESTPROMPTREQUIRESAPPROVAL Verify Prompt returns true

            policy = derivux.config.ExecutionPolicy.Prompt;
            testCase.verifyTrue(policy.requiresApproval());
        end

        function testDisabledDoesNotRequireApproval(testCase)
            %TESTDISABLEDDOESNOTREQUIREAPPROVAL Verify Disabled returns false

            policy = derivux.config.ExecutionPolicy.Disabled;
            testCase.verifyFalse(policy.requiresApproval());
        end

        %% isEnabled Method Tests
        function testAutoIsEnabled(testCase)
            %TESTAUTOISENABLED Verify Auto returns true

            policy = derivux.config.ExecutionPolicy.Auto;
            testCase.verifyTrue(policy.isEnabled());
        end

        function testPromptIsEnabled(testCase)
            %TESTPROMPTISALWAYSENABLED Verify Prompt returns true

            policy = derivux.config.ExecutionPolicy.Prompt;
            testCase.verifyTrue(policy.isEnabled());
        end

        function testDisabledIsNotEnabled(testCase)
            %TESTDISABLEDISNOTENABLED Verify Disabled returns false

            policy = derivux.config.ExecutionPolicy.Disabled;
            testCase.verifyFalse(policy.isEnabled());
        end

        %% Parameterized Tests for Consistency
        function testEnumIsValidClass(testCase, EnumValues)
            %TESTENUMISVALIDCLASS Verify all enum values are correct class

            testCase.verifyClass(EnumValues, 'derivux.config.ExecutionPolicy');
        end

        function testRequiresApprovalReturnsLogical(testCase, EnumValues)
            %TESTREQUIRESAPPROVALRETURNSLOGICAL Verify method returns logical

            result = EnumValues.requiresApproval();
            testCase.verifyClass(result, 'logical');
        end

        function testIsEnabledReturnsLogical(testCase, EnumValues)
            %TESTISENABLEDRETURNSLOGICAL Verify method returns logical

            result = EnumValues.isEnabled();
            testCase.verifyClass(result, 'logical');
        end

        %% Mutual Exclusivity Tests
        function testOnlyPromptRequiresApproval(testCase)
            %TESTONLYPROMPTREQUIRESAPPROVAL Verify only Prompt requires approval

            auto = derivux.config.ExecutionPolicy.Auto;
            prompt = derivux.config.ExecutionPolicy.Prompt;
            disabled = derivux.config.ExecutionPolicy.Disabled;

            approvalRequired = [auto.requiresApproval(), ...
                               prompt.requiresApproval(), ...
                               disabled.requiresApproval()];

            testCase.verifyEqual(sum(approvalRequired), 1, ...
                'Exactly one policy should require approval');
            testCase.verifyTrue(prompt.requiresApproval(), ...
                'That policy should be Prompt');
        end

        function testOnlyDisabledIsNotEnabled(testCase)
            %TESTONLYDISABLEDISNOTENABLED Verify only Disabled is not enabled

            auto = derivux.config.ExecutionPolicy.Auto;
            prompt = derivux.config.ExecutionPolicy.Prompt;
            disabled = derivux.config.ExecutionPolicy.Disabled;

            isEnabled = [auto.isEnabled(), ...
                        prompt.isEnabled(), ...
                        disabled.isEnabled()];

            testCase.verifyEqual(sum(~isEnabled), 1, ...
                'Exactly one policy should be disabled');
            testCase.verifyFalse(disabled.isEnabled(), ...
                'That policy should be Disabled');
        end
    end
end
