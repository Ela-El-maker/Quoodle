'use client';

import React, { useMemo, useState } from 'react';
import {
  User, Mail, Shield, Key, Clock, Plus, Trash2,
  CheckCircle, Fingerprint, Smartphone, Monitor, Globe,
  LogOut, X
} from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

interface ApiKey {
  id: string;
  name: string;
  prefix: string;
  created: string;
  lastUsed: string;
  scopes: string[];
}

interface Session {
  id: string;
  device: string;
  os: string;
  browser: string;
  ip: string;
  location: string;
  startedAt: string;
  lastActive: string;
  current: boolean;
}

const roleColors: Record<string, string> = {
  admin: 'bg-primary/10 text-primary border-primary/20',
  operator: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
  viewer: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
};

const tabs = ['Profile', 'Security', 'API Keys', 'Sessions'] as const;
type Tab = typeof tabs[number];

export default function ProfileContent() {
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState<Tab>('Profile');
  const [displayName, setDisplayName] = useState(user?.name ?? 'Ops Team');
  const [editingName, setEditingName] = useState(false);
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([]);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [showNewKeyModal, setShowNewKeyModal] = useState(false);
  const [newKeyName, setNewKeyName] = useState('');
  const [twoFAEnabled, setTwoFAEnabled] = useState(false);
  const [webAuthnKeys, setWebAuthnKeys] = useState<Array<{ id: string; name: string; registered: string; lastUsed: string }>>([]);

  const role = user?.role ?? 'operator';
  const email = user?.email ?? 'ops.team@quoodle.io';
  const revocableSessions = useMemo(() => sessions.filter((session) => !session.current), [sessions]);

  const generateApiKey = () => {
    if (!newKeyName.trim()) {
      toast.error('Key name is required');
      return;
    }
    toast.info('API key provisioning is not configured in this environment yet.');
    setNewKeyName('');
    setShowNewKeyModal(false);
  };

  const revokeKey = (id: string) => {
    setApiKeys((prev) => prev.filter((k) => k.id !== id));
    toast.success('API key revoked');
  };

  const revokeSession = (id: string) => {
    setSessions((prev) => prev.filter((s) => s.id !== id));
    toast.success('Session terminated');
  };

  return (
    <div className="space-y-6 fade-in max-w-4xl">
      <div className="flex items-center gap-4">
        <div className="w-14 h-14 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
          <User size={24} className="text-primary" />
        </div>
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">{displayName}</h1>
          <div className="flex items-center gap-2 mt-1">
            <span className="text-sm text-muted-foreground">{email}</span>
            <span className={`text-[10px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded-full border ${roleColors[role]}`}>
              {role}
            </span>
          </div>
        </div>
      </div>

      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 w-fit">
        {tabs.map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-1.5 rounded-md text-xs font-medium transition-all ${
              activeTab === tab ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {activeTab === 'Profile' && (
        <div className="space-y-4">
          <div className="bg-card border border-border rounded-lg p-5 space-y-4">
            <h2 className="text-sm font-semibold">Account Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="text-xs text-muted-foreground mb-1.5 block">Display Name</label>
                {editingName ? (
                  <div className="flex items-center gap-2">
                    <input
                      value={displayName}
                      onChange={(e) => setDisplayName(e.target.value)}
                      className="flex-1 px-3 py-1.5 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
                    />
                    <button
                      onClick={() => {
                        setEditingName(false);
                        toast.success('Display name updated');
                      }}
                      className="px-3 py-1.5 text-xs bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
                    >
                      Save
                    </button>
                    <button onClick={() => setEditingName(false)} className="text-muted-foreground hover:text-foreground">
                      <X size={14} />
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <span className="text-sm">{displayName}</span>
                    <button onClick={() => setEditingName(true)} className="text-xs text-primary hover:underline">Edit</button>
                  </div>
                )}
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1.5 block">Email Address</label>
                <div className="flex items-center gap-2">
                  <Mail size={13} className="text-muted-foreground" />
                  <span className="text-sm">{email}</span>
                  <span className="text-[10px] text-green-400 bg-green-500/10 px-1.5 py-0.5 rounded-full">Verified</span>
                </div>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1.5 block">Role</label>
                <span className={`text-xs font-semibold uppercase tracking-wider px-2 py-1 rounded-full border ${roleColors[role]}`}>
                  {role}
                </span>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1.5 block">Account Status</label>
                <span className="text-xs text-green-400 bg-green-500/10 px-2 py-1 rounded-full border border-green-500/20">Active</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'Security' && (
        <div className="space-y-4">
          <div className="bg-card border border-border rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-lg bg-green-500/10 flex items-center justify-center">
                  <Smartphone size={16} className="text-green-400" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold">Two-Factor Authentication</h3>
                  <p className="text-xs text-muted-foreground">TOTP via authenticator app</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <span className={`text-xs px-2 py-0.5 rounded-full ${twoFAEnabled ? 'bg-green-500/10 text-green-400' : 'bg-muted text-muted-foreground'}`}>
                  {twoFAEnabled ? 'Enabled' : 'Disabled'}
                </span>
                <button
                  onClick={() => {
                    setTwoFAEnabled(!twoFAEnabled);
                    toast.success(twoFAEnabled ? '2FA disabled' : '2FA enabled');
                  }}
                  className={`relative w-10 h-5 rounded-full transition-colors ${twoFAEnabled ? 'bg-green-500' : 'bg-muted'}`}
                >
                  <span className={`absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${twoFAEnabled ? 'translate-x-5' : 'translate-x-0.5'}`} />
                </button>
              </div>
            </div>
            {twoFAEnabled && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/30 rounded-md px-3 py-2">
                <CheckCircle size={12} className="text-green-400" />
                Authenticator app configured - Last verification data will appear once security telemetry is connected.
              </div>
            )}
          </div>

          <div className="bg-card border border-border rounded-lg p-5">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Fingerprint size={16} className="text-primary" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold">WebAuthn / Passkeys</h3>
                  <p className="text-xs text-muted-foreground">Hardware keys and biometric authenticators</p>
                </div>
              </div>
              <button
                onClick={() => toast.info('Passkey registration API is not available in this environment yet.')}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-md hover:bg-primary/20 transition-colors"
              >
                <Plus size={12} /> Register Key
              </button>
            </div>
            <div className="space-y-2">
              {webAuthnKeys.length === 0 && (
                <div className="px-3 py-3 text-xs text-muted-foreground bg-muted/30 rounded-md">
                  No passkeys registered.
                </div>
              )}
              {webAuthnKeys.map((wk) => (
                <div key={wk.id} className="flex items-center justify-between px-3 py-2.5 bg-muted/30 rounded-md">
                  <div className="flex items-center gap-2.5">
                    <Key size={13} className="text-muted-foreground" />
                    <div>
                      <p className="text-xs font-medium">{wk.name}</p>
                      <p className="text-[10px] text-muted-foreground">Registered {wk.registered} - Last used {wk.lastUsed}</p>
                    </div>
                  </div>
                  <button
                    onClick={() => {
                      setWebAuthnKeys((prev) => prev.filter((k) => k.id !== wk.id));
                      toast.success('Key removed');
                    }}
                    className="p-1 text-muted-foreground hover:text-red-400 transition-colors"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-card border border-border rounded-lg p-5">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-lg bg-amber-500/10 flex items-center justify-center">
                  <Shield size={16} className="text-amber-400" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold">Password</h3>
                  <p className="text-xs text-muted-foreground">Password metadata sync is not configured.</p>
                </div>
              </div>
              <button
                onClick={() => toast.info('Password management API is not available in this environment yet.')}
                className="text-xs text-primary hover:underline"
              >
                Change Password
              </button>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'API Keys' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-xs text-muted-foreground">{apiKeys.length} active key{apiKeys.length !== 1 ? 's' : ''}</p>
            <button
              onClick={() => setShowNewKeyModal(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors"
            >
              <Plus size={12} /> Generate Key
            </button>
          </div>

          {showNewKeyModal && (
            <div className="bg-card border border-border rounded-lg p-4 space-y-3">
              <h3 className="text-sm font-semibold">New API Key</h3>
              <input
                placeholder="Key name (e.g. CI/CD Pipeline)"
                value={newKeyName}
                onChange={(e) => setNewKeyName(e.target.value)}
                className="w-full px-3 py-1.5 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
              <div className="flex items-center gap-2">
                <button
                  onClick={generateApiKey}
                  className="px-3 py-1.5 text-xs bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
                >
                  Generate
                </button>
                <button onClick={() => setShowNewKeyModal(false)} className="text-xs text-muted-foreground hover:text-foreground">Cancel</button>
              </div>
            </div>
          )}

          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border bg-muted/20">
                  <th className="px-4 py-3 text-left text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Name</th>
                  <th className="px-4 py-3 text-left text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Key Prefix</th>
                  <th className="px-4 py-3 text-left text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Scopes</th>
                  <th className="px-4 py-3 text-left text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Created</th>
                  <th className="px-4 py-3 text-left text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Last Used</th>
                  <th className="px-4 py-3 w-12" />
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {apiKeys.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-4 py-6 text-center text-xs text-muted-foreground">
                      No API keys found.
                    </td>
                  </tr>
                )}
                {apiKeys.map((key) => (
                  <tr key={key.id} className="hover:bg-muted/20 transition-colors">
                    <td className="px-4 py-3 font-medium">{key.name}</td>
                    <td className="px-4 py-3 font-mono text-muted-foreground">{key.prefix}…</td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        {key.scopes.map((scope) => (
                          <span key={scope} className="text-[10px] px-1.5 py-0.5 bg-muted rounded text-muted-foreground">{scope}</span>
                        ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-muted-foreground">{key.created}</td>
                    <td className="px-4 py-3 text-muted-foreground">{key.lastUsed}</td>
                    <td className="px-4 py-3">
                      <button onClick={() => revokeKey(key.id)} className="p-1 text-muted-foreground hover:text-red-400 transition-colors" title="Revoke key">
                        <Trash2 size={13} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'Sessions' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-xs text-muted-foreground">{sessions.length} active session{sessions.length !== 1 ? 's' : ''}</p>
            <button
              onClick={() => {
                if (revocableSessions.length === 0) return;
                setSessions((prev) => prev.filter((session) => session.current));
                toast.success('All other sessions terminated');
              }}
              disabled={revocableSessions.length === 0}
              className="flex items-center gap-1.5 text-xs text-red-400 hover:text-red-300 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <LogOut size={12} /> Revoke All Other Sessions
            </button>
          </div>
          <div className="space-y-3">
            {sessions.length === 0 && (
              <div className="bg-card border border-border rounded-lg p-4 text-xs text-muted-foreground">
                No active sessions found.
              </div>
            )}
            {sessions.map((session) => (
              <div key={session.id} className={`bg-card border rounded-lg p-4 ${session.current ? 'border-primary/30' : 'border-border'}`}>
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-3">
                    <div className="w-9 h-9 rounded-lg bg-muted/60 flex items-center justify-center flex-shrink-0 mt-0.5">
                      {session.os.includes('iOS') || session.os.includes('Android') ? (
                        <Smartphone size={16} className="text-muted-foreground" />
                      ) : (
                        <Monitor size={16} className="text-muted-foreground" />
                      )}
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium">{session.device}</span>
                        {session.current && (
                          <span className="text-[10px] text-green-400 bg-green-500/10 px-1.5 py-0.5 rounded-full">Current</span>
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">{session.os} - {session.browser}</p>
                      <div className="flex items-center gap-3 mt-1.5 text-[11px] text-muted-foreground">
                        <span className="flex items-center gap-1"><Globe size={10} /> {session.ip}</span>
                        <span>{session.location}</span>
                        <span className="flex items-center gap-1"><Clock size={10} /> {session.lastActive}</span>
                      </div>
                    </div>
                  </div>
                  {!session.current && (
                    <button
                      onClick={() => revokeSession(session.id)}
                      className="flex items-center gap-1 text-xs text-red-400 hover:text-red-300 transition-colors"
                    >
                      <LogOut size={12} /> Revoke
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
