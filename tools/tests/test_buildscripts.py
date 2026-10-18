#!/usr/bin/env python3
"""Mock-engine tests for the build/release script layer.

These run on Linux: a fake ``lkm-build`` / ``lkm-release`` on PATH records what
the stub handed it (arguments + exported config), then simulates the engine's
observable contract — early exit for --check/--help/--version, a
``dist/Coreography-<ver>.zip`` artifact for --zip. They assert the stub's own
behaviour: flag translation, env config, rejection of unsupported signing
modes, error propagation and the fleet zip-naming convention. They never fake
a Mac build: no test asserts xcodebuild/codesign/lipo output, and the
assemble-app.sh tests only cover its honest pre-flight failures.

Run:  python3 tools/tests/test_buildscripts.py
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUILD = REPO / "scripts" / "build.sh"
RELEASE = REPO / "scripts" / "release.sh"
ASSEMBLE = REPO / "scripts" / "assemble-app.sh"

MOCK_BUILD = """\
#!/usr/bin/env bash
{
  echo "ARGV_BEGIN"
  for a in "$@"; do echo "ARG:$a"; done
  echo "ARGV_END"
  echo "COREO_ARCH=${COREO_ARCH:-}"
  echo "BUILD_KIND=${BUILD_KIND:-}"
  echo "BUILD_APP_NAME=${BUILD_APP_NAME:-}"
  echo "BUILD_SWIFTPM_ASSEMBLE=${BUILD_SWIFTPM_ASSEMBLE:-}"
  echo "BUILD_PRODUCT_PATH=${BUILD_PRODUCT_PATH:-}"
  echo "BUILD_INVOKED_AS=${BUILD_INVOKED_AS:-}"
} > "$MOCK_RECORD"
nomutate=false
wantzip=false
for a in "$@"; do
  case "$a" in
    --check|--help|-h|--version) nomutate=true ;;
    --zip) wantzip=true ;;
  esac
done
if [ -n "${MOCK_FAIL:-}" ]; then
  echo "mock engine failure" >&2
  exit "$MOCK_FAIL"
fi
# Mirror the real engine: no-mutate modes exit before building; a --zip build
# leaves dist/<Product>-<version>.zip behind.
if $wantzip && ! $nomutate; then
  mkdir -p dist/Coreography.app/Contents
  printf '%s\n' '<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>9.9.9</string></dict></plist>' > dist/Coreography.app/Contents/Info.plist
  : > "dist/Coreography-9.9.9.zip"
fi
exit 0
"""

MOCK_RELEASE = """\
#!/usr/bin/env bash
{
  echo "ARGV_BEGIN"
  for a in "$@"; do echo "ARG:$a"; done
  echo "ARGV_END"
  echo "RELEASE_KIND=${RELEASE_KIND:-}"
  echo "RELEASE_APP_NAME=${RELEASE_APP_NAME:-}"
  echo "RELEASE_XCODE_PROJECT=${RELEASE_XCODE_PROJECT:-}"
  echo "RELEASE_XCODE_SCHEME=${RELEASE_XCODE_SCHEME:-}"
  echo "RELEASE_INVOKED_AS=${RELEASE_INVOKED_AS:-}"
} > "$MOCK_RECORD"
exit "${MOCK_FAIL:-0}"
"""


def host_arch():
    return subprocess.run(["uname", "-m"], capture_output=True,
                          text=True, check=True).stdout.strip()


class ScriptTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="coreo-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.fakebin = self.tmp / "bin"
        self.fakebin.mkdir()
        self.record = self.tmp / "record"
        self.repo = self.tmp / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        for source in (BUILD, RELEASE, ASSEMBLE):
            shutil.copy2(source, self.repo / "scripts" / source.name)
        self.dist = self.repo / "dist"

    def install_mock(self, name, body=MOCK_BUILD):
        path = self.fakebin / name
        path.write_text(body)
        path.chmod(0o755)

    def run_script(self, script, *args, env_extra=None):
        env = {
            "PATH": f"{self.fakebin}{os.pathsep}/usr/bin{os.pathsep}/bin",
            "MOCK_RECORD": str(self.record),
            "HOME": str(self.tmp),
        }
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            ["bash", str(self.repo / "scripts" / script.name), *args],
            env=env, cwd=self.repo, capture_output=True, text=True)

    def recorded(self):
        self.assertTrue(self.record.exists(),
                        "engine was not invoked (no record written)")
        lines = self.record.read_text().splitlines()
        args = [l[4:] for l in lines if l.startswith("ARG:")]
        env = {}
        for l in lines:
            if "=" in l and not l.startswith("ARG") and "BEGIN" not in l \
                    and "END" not in l:
                k, _, v = l.partition("=")
                env[k] = v
        return args, env


class TestBuildSh(ScriptTestCase):
    def test_missing_engine_fails_clearly(self):
        r = self.run_script(BUILD)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("lkm-build", r.stderr)

    def test_help_forwarded_without_mutation(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--help")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, _ = self.recorded()
        self.assertEqual(args, ["--help"])
        # The stub announces the arch itself since the engine can't know it.
        self.assertIn("arch=", r.stdout)
        self.assertFalse(list(self.dist.glob("*.zip")) if self.dist.exists() else [])

    def test_check_forwarded(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--check")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, env = self.recorded()
        self.assertEqual(args, ["--check"])
        self.assertEqual(env["BUILD_KIND"], "swiftpm")
        self.assertEqual(env["BUILD_APP_NAME"], "Coreography")
        self.assertEqual(env["BUILD_SWIFTPM_ASSEMBLE"], "scripts/assemble-app.sh")
        self.assertEqual(env["BUILD_PRODUCT_PATH"], "dist/Coreography.app")
        self.assertEqual(env["BUILD_INVOKED_AS"], "scripts/build.sh")

    def test_check_does_not_rename_stale_zip(self):
        self.install_mock("lkm-build")
        self.dist.mkdir()
        stale = self.dist / "Coreography-0.0.0.zip"
        stale.touch()
        r = self.run_script(BUILD, "--check", "--zip")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(stale.exists(), "--check must not mutate anything")
        self.assertFalse((self.dist / "Coreography-v0.0.0-macos-x86_64.zip").exists())

    def test_args_forwarded_verbatim(self):
        self.install_mock("lkm-build")
        r = self.run_script(
            BUILD, "--clean", "--debug", "--run", "--zip", "--no-reveal")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, env = self.recorded()
        self.assertEqual(
            args, ["--clean", "--debug", "--run", "--zip", "--no-reveal"])
        self.assertEqual(env["COREO_ARCH"], host_arch())

    def test_universal_consumed_to_env_not_forwarded(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--universal", "--zip")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, env = self.recorded()
        self.assertEqual(args, ["--zip"])
        self.assertEqual(env["COREO_ARCH"], "universal")

    def test_zip_renamed_to_fleet_convention_universal(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--universal", "--zip")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.dist / "Coreography-v9.9.9-macos-universal.zip").exists())
        self.assertFalse((self.dist / "Coreography-9.9.9.zip").exists())

    def test_zip_renamed_to_fleet_convention_host_arch(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--zip")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(
            (self.dist / f"Coreography-v9.9.9-macos-{host_arch()}.zip").exists())

    def test_newer_stale_archive_is_not_relabelled(self):
        self.install_mock("lkm-build")
        self.dist.mkdir()
        stale = self.dist / "Coreography-0.0.1.zip"
        stale.write_bytes(b"old architecture")
        os.utime(stale, (4_000_000_000, 4_000_000_000))
        result = self.run_script(BUILD, "--universal", "--zip")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.dist / "Coreography-v9.9.9-macos-universal.zip").exists())
        self.assertEqual(stale.read_bytes(), b"old architecture")

    def test_unsupported_version_overrides_do_not_claim_success(self):
        self.install_mock("lkm-build")
        for flag in ("--app-version", "--build"):
            with self.subTest(flag=flag):
                result = self.run_script(BUILD, flag, "12")
                self.assertNotEqual(result.returncode, 0)

    def test_arch_env_override(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--zip", env_extra={"COREO_ARCH": "arm64"})
        self.assertEqual(r.returncode, 0, r.stderr)
        _, env = self.recorded()
        self.assertEqual(env["COREO_ARCH"], "arm64")
        self.assertTrue((self.dist / "Coreography-v9.9.9-macos-arm64.zip").exists())

    def test_reject_dev_signing(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--dev")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.record.exists(), "engine must not be invoked")
        self.assertIn("sign", r.stderr)

    def test_reject_developer_id_signing(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--developer-id")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.record.exists(), "engine must not be invoked")
        self.assertIn("sign", r.stderr)

    def test_reject_non_adhoc_sign_mode_env(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, env_extra={"BUILD_SIGN_MODE": "dev"})
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.record.exists(), "engine must not be invoked")
        self.assertIn("ad-hoc", r.stderr)

    def test_reject_unknown_arch(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, env_extra={"COREO_ARCH": "mips"})
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.record.exists(), "engine must not be invoked")
        self.assertIn("COREO_ARCH", r.stderr)

    def test_engine_failure_propagates(self):
        self.install_mock("lkm-build")
        r = self.run_script(BUILD, "--zip", env_extra={"MOCK_FAIL": "3"})
        self.assertEqual(r.returncode, 3)
        self.assertFalse(list(self.dist.glob("Coreography-v*.zip")) if self.dist.exists()
                         else [])


class TestReleaseSh(ScriptTestCase):
    def test_missing_engine_fails_clearly(self):
        r = self.run_script(RELEASE)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("lkm-release", r.stderr)

    def test_check_forwarded_with_config(self):
        self.install_mock("lkm-release", MOCK_RELEASE)
        r = self.run_script(RELEASE, "--check")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, env = self.recorded()
        self.assertEqual(args, ["--check"])
        self.assertEqual(env["RELEASE_KIND"], "xcode")
        self.assertEqual(env["RELEASE_APP_NAME"], "Coreography")
        self.assertEqual(env["RELEASE_XCODE_PROJECT"], "Coreography.xcodeproj")
        self.assertEqual(env["RELEASE_XCODE_SCHEME"], "Coreography")
        self.assertEqual(env["RELEASE_INVOKED_AS"], "scripts/release.sh")

    def test_version_and_push_forwarded(self):
        self.install_mock("lkm-release", MOCK_RELEASE)
        r = self.run_script(RELEASE, "0.2.0", "--push")
        self.assertEqual(r.returncode, 0, r.stderr)
        args, _ = self.recorded()
        self.assertEqual(args, ["0.2.0", "--push"])

    def test_engine_failure_propagates(self):
        self.install_mock("lkm-release", MOCK_RELEASE)
        r = self.run_script(RELEASE, env_extra={"MOCK_FAIL": "7"})
        self.assertEqual(r.returncode, 7)


class TestAssembleSh(ScriptTestCase):
    def test_rejects_unknown_option(self):
        r = self.run_script(ASSEMBLE, "--bogus")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unknown option", r.stderr)

    def test_rejects_unknown_arch(self):
        r = self.run_script(ASSEMBLE, env_extra={"COREO_ARCH": "ppc"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("COREO_ARCH", r.stderr)

    @unittest.skipIf(shutil.which("xcodebuild"), "macOS-only path")
    def test_fails_clearly_without_xcodebuild(self):
        # Honest failure, not a faked Mac success: on Linux the toolchain guard
        # must stop the script before any build claim.
        r = self.run_script(ASSEMBLE, "--debug")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("xcodebuild", r.stderr)


class TestScriptFileProperties(unittest.TestCase):
    def test_tooling_tests_preserve_preexisting_build_outputs(self):
        with tempfile.TemporaryDirectory(prefix="coreo-isolation-") as temporary:
            fixture = Path(temporary)
            (fixture / "scripts").mkdir()
            (fixture / "tools/tests").mkdir(parents=True)
            for source in (BUILD, RELEASE, ASSEMBLE):
                shutil.copy2(source, fixture / "scripts" / source.name)
            copied_tests = fixture / "tools/tests/test_buildscripts.py"
            shutil.copy2(__file__, copied_tests)
            output = fixture / "dist/keep.zip"
            output.parent.mkdir()
            output.write_bytes(b"existing developer output")
            result = subprocess.run(
                [sys.executable, str(copied_tests), "TestBuildSh.test_check_forwarded"],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.exists(), "Tests must not remove developer build outputs")

    def test_scripts_are_executable(self):
        for s in (BUILD, RELEASE, ASSEMBLE):
            self.assertTrue(os.access(s, os.X_OK), f"{s} is not executable")

    def test_bash_syntax(self):
        for s in (BUILD, RELEASE, ASSEMBLE):
            r = subprocess.run(["bash", "-n", str(s)], capture_output=True)
            self.assertEqual(r.returncode, 0, f"{s}: {r.stderr.decode()}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
