import Foundation
import Testing
@testable import CloudSessionManager

/// Covers parsing the version out of `aws --version` output, across the v2
/// (stdout) format and assorted spacing.
@Suite("AWS CLI version parsing")
struct CLIVersionTests {

    @Test func parsesStandardV2Output() {
        let output = "aws-cli/2.35.15 Python/3.14.6 Darwin/25.5.0 source/arm64"
        #expect(AWSCLIVersion.parse(output) == "2.35.15")
    }

    @Test func parsesWhenVersionIsFirstAmongExtraWhitespace() {
        let output = "\naws-cli/1.29.0  Python/3.11.0 Linux/6.1\n"
        #expect(AWSCLIVersion.parse(output) == "1.29.0")
    }

    @Test func returnsNilWhenNoVersionToken() {
        #expect(AWSCLIVersion.parse("command not found: aws") == nil)
        #expect(AWSCLIVersion.parse("") == nil)
    }

    /// Profile-selecting env vars are stripped so a stale `AWS_PROFILE`
    /// inherited from the launching shell can't break `aws` subprocesses; the
    /// rest of the environment is passed through untouched.
    @Test func subprocessEnvironmentStripsProfileVars() {
        let env = AppState.awsSubprocessEnvironment([
            "AWS_PROFILE": "stridyn-dev",
            "AWS_DEFAULT_PROFILE": "old",
            "PATH": "/usr/bin",
            "AWS_REGION": "us-west-2",
        ])
        #expect(env["AWS_PROFILE"] == nil)
        #expect(env["AWS_DEFAULT_PROFILE"] == nil)
        #expect(env["PATH"] == "/usr/bin")
        #expect(env["AWS_REGION"] == "us-west-2")
    }

    /// The official installer command is meant to paste as one runnable line —
    /// the `\` continuations in the literal must collapse, not leave newlines.
    @Test func officialInstallCommandIsSingleLine() {
        let command = AppState.cliOfficialInstallCommand
        #expect(!command.contains("\n"))
        #expect(command.contains("curl"))
        #expect(command.contains("installer -pkg AWSCLIV2.pkg"))
    }
}
