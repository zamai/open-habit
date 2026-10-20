#!/usr/bin/env python3
"""Run one release with the vault identity in a disposable signing keychain."""
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile


def security(*args, data=None):
    result = subprocess.run(['security', *args], input=data, capture_output=True)
    if result.returncode:
        # Never include command arguments: some contain the temporary password.
        raise RuntimeError(f'security {args[0]} failed (exit {result.returncode})')
    return result.stdout.decode()


def search_list():
    return shlex.split(security('list-keychains', '-d', 'user'))


def vault_value(reference):
    if not re.fullmatch(r'op://[a-z0-9]{26}/[a-z0-9]{26}/[a-z_]+', reference):
        raise RuntimeError('Signing references must use immutable vault and item IDs')
    result = subprocess.run(['op', 'read', '--no-newline', reference], capture_output=True)
    if result.returncode:
        raise RuntimeError('Could not read the signing identity from the Agents vault')
    return result.stdout


def main():
    if len(sys.argv) < 3:
        raise RuntimeError('Usage: with-signing-keychain.py CONFIG COMMAND [ARGUMENTS...]')
    config = json.loads(Path(sys.argv[1]).read_text())
    if not all(config.get(field) for field in ['signing_private_key', 'signing_certificate']):
        raise RuntimeError('Release configuration needs signing_private_key and signing_certificate vault references')
    private_key = vault_value(config['signing_private_key'])
    certificate = vault_value(config['signing_certificate'])
    original_search = search_list()
    child = None

    def stop(signum, _frame):
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signum)
        raise SystemExit(128 + signum)

    for signum in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(signum, stop)

    with tempfile.TemporaryDirectory(prefix='open-habit-signing.') as directory:
        keychain = str(Path(directory) / 'build.keychain-db')
        password = secrets.token_urlsafe(32)
        created = False
        try:
            security('create-keychain', '-p', password, keychain)
            created = True
            security('set-keychain-settings', '-lut', '3600', keychain)
            security('unlock-keychain', '-p', password, keychain)
            security('import', '/dev/stdin', '-k', keychain, '-t', 'priv', '-f', 'openssl',
                     '-P', '', '-x', '-T', '/usr/bin/codesign', data=private_key)
            security('import', '/dev/stdin', '-k', keychain, '-t', 'cert', data=certificate)
            del private_key, certificate
            security('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
                     '-s', '-k', password, keychain)
            security('list-keychains', '-d', 'user', '-s', keychain, *original_search)
            identities = security('find-identity', '-v', '-p', 'codesigning', keychain)
            match = re.search(r'\b[0-9A-Fa-f]{40}\b', identities)
            if not match:
                raise RuntimeError('The vault identity is not valid for code signing')
            identity = match.group()
            probe = str(Path(directory) / 'signing-probe')
            shutil.copyfile('/usr/bin/true', probe)
            os.chmod(probe, 0o700)
            # Check actual private-key use before starting an expensive archive.
            result = subprocess.run(['codesign', '--force', '--sign', identity,
                                     '--timestamp=none', probe], capture_output=True, timeout=15)
            if result.returncode:
                raise RuntimeError('Non-interactive signing preflight failed')
            print('Temporary signing keychain ready; non-interactive signing verified.', flush=True)
            env = dict(os.environ, OPEN_HABIT_SIGNING_KEYCHAIN=keychain)
            child = subprocess.Popen(sys.argv[2:], env=env, start_new_session=True)
            return child.wait()
        finally:
            if child is not None and child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
            if created:
                # Preserve other keychains added or removed while the release ran.
                try:
                    remaining = [path for path in search_list()
                                 if Path(path).resolve() != Path(keychain).resolve()]
                    security('list-keychains', '-d', 'user', '-s', *remaining)
                finally:
                    security('delete-keychain', keychain)
                print('Temporary signing keychain removed.', flush=True)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except subprocess.TimeoutExpired:
        print('Signing preflight timed out; no release was started.', file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
