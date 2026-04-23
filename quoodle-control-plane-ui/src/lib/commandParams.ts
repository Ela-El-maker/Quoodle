import { resolveCommandMethod } from '@/lib/commandMethodResolver';

const COMMAND_PARAM_TEMPLATES: Record<string, Record<string, unknown>> = {
  download_file: { path: 'C:\\ProgramData\\Quoodle\\device_id', max_bytes: 4096 },
  upload_file: { artifact_id: '<artifact-id>', destination: 'C:\\Users\\Public\\uploaded.bin', overwrite: true },
  create_directory: { path: 'C:\\Users\\Public\\quoodle_test', recursive: true },
  create_file: { path: 'C:\\Users\\Public\\quoodle_test\\note.txt', overwrite: true },
  delete_file: { path: 'C:\\Users\\Public\\quoodle_test\\note.txt', confirm: true },
  delete_directory: { path: 'C:\\Users\\Public\\quoodle_test', confirm: true },
  kill_process: { pid: 1234 },
  kill_process_tree: { pid: 1234 },
};

const COMMAND_REQUIRED_PARAM_HINTS: Record<string, string> = {
  download_file: 'Required: path',
  upload_file: 'Required: artifact_id, destination',
  create_directory: 'Required: path',
  create_file: 'Required: path',
  delete_file: 'Required: path, confirm=true',
  delete_directory: 'Required: path, confirm=true',
  kill_process: 'Required: pid',
  kill_process_tree: 'Required: pid',
};

function isAcceptedValue(value: unknown): boolean {
  if (value === true || value === 1) return true;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
  }
  return false;
}

function parsePositiveInteger(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isInteger(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

export function defaultParamsForCommand(method: string): Record<string, unknown> {
  const resolved = resolveCommandMethod(method);
  return COMMAND_PARAM_TEMPLATES[resolved] ?? {};
}

export function requiredParamsHintForCommand(method: string): string | null {
  const resolved = resolveCommandMethod(method);
  return COMMAND_REQUIRED_PARAM_HINTS[resolved] ?? null;
}

export function validateCommandParams(method: string, params: Record<string, unknown>): string | null {
  const resolved = resolveCommandMethod(method);
  const path = typeof params.path === 'string' ? params.path.trim() : '';

  switch (resolved) {
    case 'download_file':
    case 'create_directory':
    case 'create_file':
      if (!path) return 'Missing required field: path';
      return null;
    case 'upload_file': {
      const artifactId = typeof params.artifact_id === 'string' ? params.artifact_id.trim() : '';
      const destination = typeof params.destination === 'string' ? params.destination.trim() : '';
      if (!artifactId) return 'Missing required field: artifact_id';
      if (!destination) return 'Missing required field: destination';
      return null;
    }
    case 'delete_file':
    case 'delete_directory':
      if (!path) return 'Missing required field: path';
      if (!isAcceptedValue(params.confirm)) return 'Missing required field: confirm=true';
      return null;
    case 'kill_process':
    case 'kill_process_tree': {
      const pid = parsePositiveInteger(params.pid);
      if (pid == null || pid < 2) return 'Missing/invalid required field: pid (integer >= 2)';
      return null;
    }
    default:
      return null;
  }
}
