#!/usr/bin/env python3
"""Mock-engine tests for the build/release script layer.

These run on Linux: a fake ``lkm-build`` / ``lkm-release`` on PATH records what
the stub handed it (arguments + exported config), then simulates the engine's
observable contract — early exit for --check/--help/--version, a
``dist/Coreography-<ver>.zip`` artifact for --zip. They assert the stub's own
behaviour: flag translation, env config, rejection of unsupported signing
modes, error propagation and the fleet zip-naming convention. They never fake
a Mac build: no test asserts xcodebuild/codesign/lipo output, and the
assemble-app.sh tests only cover its honest pre-flight failures and the
settings it hands xcodebuild.

Run:  python3 tools/tests/test_buildscripts.py
"""

import os
import json
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

# Records the settings assemble-app.sh passes, then fails like a broken build so
# the script stops before staging anything.
MOCK_XCODEBUILD = """\
#!/usr/bin/env bash
for a in "$@"; do echo "ARG:$a"; done > "$MOCK_RECORD"
exit 65
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
            if "=" in l and not l.startswith("ARG:"):
                k, _, v = l.partition("=")
                env[k] = v
        return args, env


class TestBuildSh(ScriptTestCase):
    def test_recorded_environment_preserves_marker_words(self):
        self.record.write_text(
            "ARGV_BEGIN\nARG:--option=value\nARGV_END\n"
            "BUILD_SCHEME=BUILD_END_TO_END\nARG_SETTINGS=kept\n"
        )
        args, env = self.recorded()
        self.assertEqual(args, ["--option=value"])
        self.assertEqual(env, {"BUILD_SCHEME": "BUILD_END_TO_END", "ARG_SETTINGS": "kept"})

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
        self.assertFalse((self.dist / f"Coreography-v0.0.0-macos-{host_arch()}.zip").exists())

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

    def write_project(self, *versions):
        project = self.repo / "Coreography.xcodeproj"
        project.mkdir()
        lines = [f"\t\t\t\tMARKETING_VERSION = {v};" for v in versions]
        (project / "project.pbxproj").write_text("\n".join(lines) + "\n")

    def build_number_passed(self, *versions):
        self.write_project(*versions)
        self.install_mock("xcodebuild", MOCK_XCODEBUILD)
        r = self.run_script(ASSEMBLE)
        if not self.record.exists():
            return None, r
        args, _ = self.recorded()
        numbers = [a.partition("=")[2] for a in args if a.startswith("CURRENT_PROJECT_VERSION=")]
        self.assertEqual(len(numbers), 1, args)
        return numbers[0], r

    def test_build_number_follows_the_marketing_version(self):
        # macOS tells builds of one bundle apart by CFBundleVersion; a constant
        # one let the widget gallery keep an older release's widget list.
        for version, expected in (("0.5.0", "500"), ("0.5.1", "501"),
                                  ("1.2", "10200"), ("2.10.3", "21003")):
            with self.subTest(version=version):
                self.setUp()
                number, r = self.build_number_passed(version, version)
                self.assertEqual(number, expected, r.stderr)

    def test_build_number_uses_the_real_project_version(self):
        shutil.copytree(REPO / "Coreography.xcodeproj", self.repo / "Coreography.xcodeproj")
        self.install_mock("xcodebuild", MOCK_XCODEBUILD)
        self.run_script(ASSEMBLE)
        args, _ = self.recorded()
        self.assertTrue(any(a.startswith("CURRENT_PROJECT_VERSION=") for a in args), args)

    def test_build_number_rejects_versions_it_cannot_order(self):
        for versions, message in ((("0.5.0", "0.4.0"), "one MARKETING_VERSION"),
                                  ((), "one MARKETING_VERSION"),
                                  (("0.100.0",), "below 100"),
                                  (("0.5.0-beta",), "X.Y[.Z]")):
            with self.subTest(versions=versions):
                self.setUp()
                number, r = self.build_number_passed(*versions)
                self.assertIsNone(number, "xcodebuild ran despite an unusable version")
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(message, r.stderr)


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
                [sys.executable, str(copied_tests), "-k", "TestBuildSh"],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.exists(), "Tests must not remove developer build outputs")
            self.assertIn("test_zip_renamed_to_fleet_convention_universal", result.stderr)
            self.assertIn("test_newer_stale_archive_is_not_relabelled", result.stderr)

    def test_scripts_are_executable(self):
        for s in (BUILD, RELEASE, ASSEMBLE):
            self.assertTrue(os.access(s, os.X_OK), f"{s} is not executable")

    def test_bash_syntax(self):
        for s in (BUILD, RELEASE, ASSEMBLE):
            r = subprocess.run(["bash", "-n", str(s)], capture_output=True)
            self.assertEqual(r.returncode, 0, f"{s}: {r.stderr.decode()}")


class TestReleaseSmoke(unittest.TestCase):
    def run_smoke(self, snapshot):
        workflow = (REPO / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Smoke-test embedded CLI\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        script = "\n".join(line[10:] for line in step.splitlines() if line.startswith("          "))
        with tempfile.TemporaryDirectory(prefix="coreo-release-gate-") as temporary:
            fixture = Path(temporary)
            cli = fixture / "dist/Coreography.app/Contents/Helpers/coreo"
            cli.parent.mkdir(parents=True)
            cli.write_text(
                "#!/usr/bin/env python3\nimport os\nprint(os.environ['COREO_FIXTURE'])\n"
            )
            cli.chmod(0o755)
            validator = REPO / "tools/check_snapshot.py"
            if validator.exists():
                (fixture / "tools").mkdir()
                shutil.copy2(validator, fixture / "tools/check_snapshot.py")
            return subprocess.run(
                ["bash", "-c", script], cwd=fixture, capture_output=True, text=True,
                env={"PATH": "/usr/bin:/bin", "RUNNER_TEMP": temporary,
                     "COREO_FIXTURE": json.dumps(snapshot)}, timeout=10,
            )

    @staticmethod
    def snapshot():
        return {
            "cpuPercentOfMachine": {"availability": "measured", "numericValue": 25},
            "cpuSystemPercentOfMachine": {"availability": "measured", "numericValue": 5},
            "memoryUsedBytes": {"availability": "estimated", "numericValue": 4096},
            "inventory": {"physicalMemoryBytes": 8192, "logicalCPUCount": 2},
            "coreBusyPercent": [
                {"availability": "measured", "numericValue": 40},
                {"availability": "measured", "numericValue": 10},
            ],
            "thermalPressure": {"availability": "measured", "numericValue": 0},
            "memory": {
                "appBytes": {"availability": "estimated", "numericValue": 2048},
                "wiredBytes": {"availability": "measured", "numericValue": 1024},
                "compressedBytes": {"availability": "measured", "numericValue": 1024},
                "cachedBytes": {"availability": "estimated", "numericValue": 512},
                "compressionRatio": {"availability": "measured", "numericValue": 2.5},
                "swapUsedBytes": {"availability": "measured", "numericValue": 0},
                "swapTotalBytes": {"availability": "measured", "numericValue": 0},
                "pageInBytesPerSecond": {"availability": "measured", "numericValue": 0},
                "swapInBytesPerSecond": {"availability": "measured", "numericValue": 0},
                "swapOutBytesPerSecond": {"availability": "measured", "numericValue": 0},
                "pressure": {"availability": "measured", "numericValue": 1},
            },
        }

    def test_release_gate_accepts_valid_native_measurements(self):
        result = self.run_smoke(self.snapshot())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_release_gate_rejects_unavailable_cpu(self):
        snapshot = self.snapshot()
        snapshot["cpuPercentOfMachine"] = {"availability": "unavailable", "reason": "Fixture"}
        self.assertNotEqual(self.run_smoke(snapshot).returncode, 0)

    def test_release_gate_rejects_invalid_values(self):
        for key, value in (("cpuPercentOfMachine", 101), ("memoryUsedBytes", 8193), ("cpuSystemPercentOfMachine", 26),
                           ("cpuPercentOfMachine", True), ("memoryUsedBytes", float("nan"))):
            with self.subTest(key=key, value=value):
                snapshot = self.snapshot()
                snapshot[key]["numericValue"] = value
                self.assertNotEqual(self.run_smoke(snapshot).returncode, 0)

    def test_release_gate_requires_one_measured_share_per_core(self):
        for cores in (None, [{"availability": "measured", "numericValue": 40}],
                      [{"availability": "measured", "numericValue": 40}, {"availability": "measured", "numericValue": 101}],
                      [{"availability": "measured", "numericValue": 40}, {"availability": "collecting"}]):
            with self.subTest(cores=cores):
                snapshot = self.snapshot()
                if cores is None:
                    del snapshot["coreBusyPercent"]
                else:
                    snapshot["coreBusyPercent"] = cores
                self.assertNotEqual(self.run_smoke(snapshot).returncode, 0)

    def test_release_gate_rejects_invalid_memory_detail(self):
        cases = (
            ("appBytes", {"availability": "estimated", "numericValue": 1024}),
            ("pressure", {"availability": "measured", "numericValue": 4}),
            ("swapUsedBytes", {"availability": "measured", "numericValue": 1}),
            ("swapInBytesPerSecond", {"availability": "collecting"}),
            ("compressionRatio", {"availability": "unavailable", "reason": "Fixture"}),
        )
        for key, value in cases:
            with self.subTest(key=key):
                snapshot = self.snapshot()
                snapshot["memory"][key] = value
                self.assertNotEqual(self.run_smoke(snapshot).returncode, 0)

    def test_release_gate_rejects_unknown_or_missing_thermal_pressure(self):
        for value in ({"availability": "measured", "numericValue": 5},
                      {"availability": "measured", "numericValue": 1.5},
                      {"availability": "unavailable", "reason": "Fixture"}):
            with self.subTest(value=value):
                snapshot = self.snapshot()
                snapshot["thermalPressure"] = value
                self.assertNotEqual(self.run_smoke(snapshot).returncode, 0)

    def test_release_gate_accepts_empty_compressor_without_ratio(self):
        snapshot = self.snapshot()
        memory = snapshot["memory"]
        memory["compressedBytes"]["numericValue"] = 0
        memory["appBytes"]["numericValue"] = 3072
        memory["compressionRatio"] = {"availability": "unavailable", "reason": "Compressor is empty"}
        self.assertEqual(self.run_smoke(snapshot).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
