'use client';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useForm } from 'react-hook-form';
import { X, Terminal, Shield, AlertTriangle, Loader2, CheckCircle2 } from 'lucide-react';
import { toast } from 'sonner';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import { randomUuid } from '@/lib/uuid';
import {
  defaultParamsForCommand,
  requiredParamsHintForCommand,
  validateCommandParams,
} from '@/lib/commandParams';
import {
  mapListDevice,
  type Device as ManagedDevice,
  type ListDeviceApi,
} from '@/app/device-management/lib/deviceManagementData';

interface DispatchCommandModalProps {
  onClose: () => void;
}

interface FormValues {
  deviceId: string;
  method: string;
  twoFactorCode: string;
  paramsJson: string;
}

interface DevicesApiResponse {
  devices?: ListDeviceApi[];
}

interface CapabilitiesResponse {
  canonical_methods?: string[];
  runtime_supported_methods?: string[];
}

interface DispatchResponse {
  command_id?: string;
  reason?: string;
  message?: string;
  errors?: Record<string, string[] | string | null> | null;
  compliance?: { failed_rules?: string[] } | null;
}

interface MethodOption {
  id: string;
  label: string;
  risk: 'low' | 'medium' | 'high';
  requires2fa: boolean;
  desc: string;
}

const MEDIUM_RISK_METHODS = new Set(['lock_screen', 'reboot_device', 'shutdown_device', 'logout_user']);
const HIGH_RISK_METHODS = new Set([
  'wipe_device',
  'factory_reset',
  'unenroll_device',
  'upload_file',
  'create_directory',
  'create_file',
  'delete_file',
  'delete_directory',
  'kill_process',
  'kill_process_tree',
]);
const TWO_FACTOR_METHODS = new Set([
  'wipe_device',
  'factory_reset',
  'shutdown_device',
  'upload_file',
  'create_directory',
  'create_file',
  'delete_file',
  'delete_directory',
  'kill_process',
  'kill_process_tree',
]);

const riskColors = {
  low: { badge: 'bg-green-500/10 border-green-500/20 text-green-400', icon: CheckCircle2 },
  medium: { badge: 'bg-amber-500/10 border-amber-500/20 text-amber-400', icon: AlertTriangle },
  high: { badge: 'bg-red-500/10 border-red-500/20 text-red-400', icon: Shield },
};

function methodRisk(method: string): MethodOption['risk'] {
  if (HIGH_RISK_METHODS.has(method)) return 'high';
  if (MEDIUM_RISK_METHODS.has(method)) return 'medium';
  return 'low';
}

function methodDescription(method: string): string {
  switch (method) {
    case 'ping':
      return 'Send a ping to verify agent connectivity and runtime response.';
    case 'lock_screen':
      return 'Lock the device screen immediately. User will need to re-authenticate.';
    case 'collect_system_info':
      return 'Collect host profile and operating system information.';
    case 'list_processes':
      return 'List active processes from the target endpoint.';
    case 'list_files':
      return 'Default scope is C:\\Users when path is omitted. Set path to C:\\ for a full-drive scan.';
    case 'upload_file':
      return 'Fetch an artifact by artifact_id and write it to destination path.';
    case 'create_directory':
      return 'Create a directory at an explicit path. Supports recursive parent creation.';
    case 'create_file':
      return 'Create an empty file at an explicit path. Use overwrite=true to truncate existing files.';
    case 'delete_file':
      return 'Hard-delete a regular file. confirm=true is required.';
    case 'delete_directory':
      return 'Hard-delete a directory recursively. confirm=true is required.';
    case 'network_info':
      return 'Collect active network interfaces and routes.';
    default:
      return 'Dispatch this command to the selected endpoint.';
  }
}

function buildMethodOptions(payload: CapabilitiesResponse | null): MethodOption[] {
  const runtime = payload?.runtime_supported_methods ?? [];
  const canonical = payload?.canonical_methods ?? [];
  const source = runtime.length > 0 ? runtime : canonical;
  const methods = Array.from(new Set(source.map((method) => method.trim()).filter(Boolean))).sort();

  return methods.map((id) => ({
    id,
    label: id,
    risk: methodRisk(id),
    requires2fa: TWO_FACTOR_METHODS.has(id),
    desc: methodDescription(id),
  }));
}

function firstValidationError(errors: DispatchResponse['errors']): string | null {
  if (!errors || typeof errors !== 'object') return null;
  for (const value of Object.values(errors)) {
    if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'string') {
      return value[0];
    }
    if (typeof value === 'string' && value.trim() !== '') {
      return value;
    }
  }
  return null;
}

function formatDispatchError(payload: DispatchResponse, statusCode: number): string {
  const validationMessage = firstValidationError(payload.errors);
  if (validationMessage) return validationMessage;

  const reason = payload.reason ?? payload.message ?? `http_${statusCode}`;
  if (reason === 'compliance_failed') {
    const rules = payload.compliance?.failed_rules ?? [];
    return rules.length > 0 ? `compliance_failed: ${rules.join(', ')}` : reason;
  }
  return reason;
}

export default function DispatchCommandModal({ onClose }: DispatchCommandModalProps) {
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [isLoadingData, setIsLoadingData] = useState(true);
  const [devices, setDevices] = useState<ManagedDevice[]>([]);
  const [methods, setMethods] = useState<MethodOption[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [commandId, setCommandId] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({
    defaultValues: { deviceId: '', method: '', twoFactorCode: '', paramsJson: '{}' },
  });

  useEffect(() => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const load = async () => {
      setIsLoadingData(true);
      try {
        const [devicesRes, capabilitiesRes] = await Promise.all([
          fetch('/api/devices?per_page=200', {
            credentials: 'include',
            cache: 'no-store',
            signal: controller.signal,
          }),
          fetch('/api/commands/capabilities', {
            credentials: 'include',
            cache: 'no-store',
            signal: controller.signal,
          }),
        ]);

        if (!devicesRes.ok || !capabilitiesRes.ok) {
          throw new Error('load_failed');
        }

        const devicesPayload = (await devicesRes.json()) as DevicesApiResponse;
        const capabilitiesPayload = (await capabilitiesRes.json()) as CapabilitiesResponse;
        setDevices((devicesPayload.devices ?? []).map(mapListDevice));
        setMethods(buildMethodOptions(capabilitiesPayload));
        setLoadError(null);
      } catch (error) {
        if ((error as Error).name === 'AbortError') return;
        console.error('dispatch-modal-load-failed', error);
        setLoadError('Failed to load data');
      } finally {
        setIsLoadingData(false);
      }
    };

    void load();
    return () => controller.abort();
  }, []);

  const selectedMethod = watch('method');
  const methodMeta = useMemo(
    () => methods.find((method) => method.id === selectedMethod),
    [methods, selectedMethod],
  );
  const requires2fa = methodMeta?.requires2fa ?? false;
  const requiredParamsHint = selectedMethod ? requiredParamsHintForCommand(selectedMethod) : null;

  useEffect(() => {
    if (!selectedMethod) {
      setValue('paramsJson', '{}');
      return;
    }
    const template = defaultParamsForCommand(selectedMethod);
    setValue('paramsJson', JSON.stringify(template, null, 2));
  }, [selectedMethod, setValue]);

  const availableDevices = useMemo(
    () => devices.filter((device) => device.status !== 'offline'),
    [devices],
  );

  const onSubmit = async (data: FormValues) => {
    let parsedParams: Record<string, unknown>;
    try {
      const parsed = JSON.parse(data.paramsJson || '{}') as unknown;
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Parameters JSON must be an object');
      }
      parsedParams = parsed as Record<string, unknown>;
    } catch {
      toast.error('Dispatch failed: invalid JSON parameters');
      return;
    }

    const clientValidation = validateCommandParams(data.method, parsedParams);
    if (clientValidation) {
      toast.error(`Dispatch failed: ${clientValidation}`);
      return;
    }

    setLoading(true);
    try {
      const resolvedMethod = resolveCommandMethod(data.method);
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          client_message_id: `dispatch-modal-${data.deviceId}-${resolvedMethod}-${randomUuid()}`,
          device_id: data.deviceId,
          method: resolvedMethod,
          params: parsedParams,
          sensitive: methodMeta?.risk === 'high' || methodMeta?.risk === 'medium',
          two_factor_code: data.twoFactorCode || undefined,
        }),
      });

      const payload = (await response.json().catch(() => ({}))) as DispatchResponse;
      if (!response.ok || !payload.command_id) {
        throw new Error(formatDispatchError(payload, response.status));
      }

      setCommandId(payload.command_id);
      setSubmitted(true);
      toast.success(`Command ${data.method} queued for ${data.deviceId}`, {
        description: `${payload.command_id} - Awaiting dispatch`,
      });
      window.setTimeout(onClose, 1200);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to load data';
      toast.error(`Dispatch failed: ${message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
      <div className="bg-card border border-border rounded-xl w-full max-w-lg shadow-2xl fade-in">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center">
              <Terminal size={14} className="text-primary" />
            </div>
            <h2 className="font-semibold text-sm">Dispatch Command</h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
            <X size={15} />
          </button>
        </div>

        {submitted ? (
          <div className="flex flex-col items-center justify-center py-12 px-5">
            <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mb-3">
              <CheckCircle2 size={24} className="text-green-400" />
            </div>
            <p className="font-semibold text-sm">Command Queued</p>
            <p className="text-xs text-muted-foreground mt-1">{commandId ?? 'Command'} - Dispatching to gateway...</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit(onSubmit)} className="p-5 space-y-4">
            {loadError && (
              <div className="text-[11px] text-red-400 bg-red-500/5 border border-red-500/20 rounded-md px-3 py-2">
                Failed to load data
              </div>
            )}

            <div>
              <label className="block text-xs font-medium mb-1.5">
                Target Device <span className="text-red-400">*</span>
              </label>
              <p className="text-[11px] text-muted-foreground mb-2">Select the device to dispatch the command to.</p>
              <select
                {...register('deviceId', { required: 'Device is required' })}
                disabled={isLoadingData || availableDevices.length === 0}
                className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 disabled:opacity-60"
              >
                <option value="">{isLoadingData ? 'Loading devices...' : 'Select a device...'}</option>
                {availableDevices.map((device) => (
                  <option key={`dispatch-dev-${device.id}`} value={device.id}>
                    {device.hostname} - {device.status}
                  </option>
                ))}
              </select>
              {errors.deviceId && (
                <p className="text-[11px] text-red-400 mt-1">{errors.deviceId.message}</p>
              )}
            </div>

            <div>
              <label className="block text-xs font-medium mb-1.5">
                Command Method <span className="text-red-400">*</span>
              </label>
              <p className="text-[11px] text-muted-foreground mb-2">Only methods approved by policy are shown.</p>
              <div className="space-y-2 max-h-56 overflow-y-auto scrollbar-thin pr-1">
                {isLoadingData && (
                  <div className="text-[11px] text-muted-foreground border border-border rounded-lg px-3 py-2.5">
                    Loading data...
                  </div>
                )}
                {!isLoadingData && methods.length === 0 && (
                  <div className="text-[11px] text-muted-foreground border border-border rounded-lg px-3 py-2.5">
                    No data available
                  </div>
                )}
                {methods.map((method) => {
                  const riskCfg = riskColors[method.risk];
                  return (
                    <label
                      key={`method-opt-${method.id}`}
                      className={`flex items-start gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                        selectedMethod === method.id
                          ? 'border-primary/50 bg-primary/5' : 'border-border hover:border-border/80 hover:bg-muted/20'
                      }`}
                    >
                      <input
                        type="radio"
                        value={method.id}
                        {...register('method', { required: 'Method is required' })}
                        className="mt-0.5 accent-blue-500"
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <span className="font-mono text-xs font-semibold">{method.label}</span>
                          <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${riskCfg.badge}`}>
                            {method.risk} risk
                          </span>
                        </div>
                        <p className="text-[11px] text-muted-foreground">{method.desc}</p>
                      </div>
                    </label>
                  );
                })}
              </div>
              {errors.method && (
                <p className="text-[11px] text-red-400 mt-1">{errors.method.message}</p>
              )}
            </div>

            {selectedMethod && (
              <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-3">
                <div className="flex items-center gap-2 mb-1">
                  <CheckCircle2 size={12} className="text-green-400" />
                  <p className="text-[11px] font-semibold text-green-400">Policy Gate: Allow</p>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  Runtime capabilities validated for selected device
                  {requires2fa && ' - 2FA required'}
                </p>
              </div>
            )}

            {requires2fa && (
              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Two-Factor Code <span className="text-red-400">*</span>
                </label>
                <p className="text-[11px] text-muted-foreground mb-2">This command requires 2FA verification. Enter your current TOTP code.</p>
                <input
                  type="text"
                  maxLength={6}
                  placeholder="000000"
                  {...register('twoFactorCode', {
                    validate: (value) => !requires2fa || value.length === 6 || '2FA code must be 6 digits',
                  })}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground font-mono tracking-widest placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                />
                {errors.twoFactorCode && (
                  <p className="text-[11px] text-red-400 mt-1">{errors.twoFactorCode.message}</p>
                )}
              </div>
            )}

            <div>
              <label className="block text-xs font-medium mb-1.5">
                Parameters (JSON, {requiredParamsHint ? 'required' : 'optional'})
              </label>
              <textarea
                {...register('paramsJson', {
                  required: requiredParamsHint ? 'Parameters are required' : false,
                  validate: (value) => {
                    if (!value || value.trim() === '') {
                      return requiredParamsHint ? 'Parameters are required' : true;
                    }
                    try {
                      const parsed = JSON.parse(value);
                      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
                        return 'Parameters must be a JSON object';
                      }
                    } catch {
                      return 'Invalid JSON';
                    }
                    return true;
                  },
                })}
                rows={8}
                className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground font-mono placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
              {requiredParamsHint && (
                <p className="text-[11px] text-amber-400 mt-1">{requiredParamsHint}</p>
              )}
              {errors.paramsJson && (
                <p className="text-[11px] text-red-400 mt-1">{errors.paramsJson.message}</p>
              )}
            </div>

            <div className="flex items-center gap-2 pt-1">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={loading || isLoadingData || methods.length === 0 || availableDevices.length === 0}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-60 active:scale-95 transition-all duration-150"
                style={{ minWidth: '120px' }}
              >
                {loading ? (
                  <>
                    <Loader2 size={13} className="animate-spin" />
                    Dispatching...
                  </>
                ) : (
                  <>
                    <Terminal size={13} />
                    Dispatch Command
                  </>
                )}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

