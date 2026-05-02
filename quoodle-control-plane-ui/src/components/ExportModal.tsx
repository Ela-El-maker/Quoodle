'use client';
import React, { useState } from 'react';
import { X, Download, FileText, FileSpreadsheet, Calendar } from 'lucide-react';
import { toast } from 'sonner';

interface ExportField {
  key: string;
  label: string;
  defaultSelected?: boolean;
}

interface ExportModalProps {
  title: string;
  fields: ExportField[];
  onClose: () => void;
  onExport?: (format: 'csv' | 'pdf', dateRange: { from: string; to: string }, selectedFields: string[]) => void;
}

const PRESETS = [
  { label: 'Last 24 hours', days: 1 },
  { label: 'Last 7 days', days: 7 },
  { label: 'Last 30 days', days: 30 },
  { label: 'Last 90 days', days: 90 },
];

function getDateOffset(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().split('T')[0];
}

function todayStr(): string {
  return new Date().toISOString().split('T')[0];
}

export default function ExportModal({ title, fields, onClose, onExport }: ExportModalProps) {
  const [format, setFormat] = useState<'csv' | 'pdf'>('csv');
  const [dateFrom, setDateFrom] = useState(getDateOffset(7));
  const [dateTo, setDateTo] = useState(todayStr());
  const [selectedFields, setSelectedFields] = useState<Set<string>>(
    new Set(fields.filter((f) => f.defaultSelected !== false).map((f) => f.key))
  );
  const [exporting, setExporting] = useState(false);

  const toggleField = (key: string) => {
    setSelectedFields((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const selectAll = () => setSelectedFields(new Set(fields.map((f) => f.key)));
  const clearAll = () => setSelectedFields(new Set());

  const applyPreset = (days: number) => {
    setDateFrom(getDateOffset(days));
    setDateTo(todayStr());
  };

  const handleExport = () => {
    if (selectedFields.size === 0) {
      toast.error('Select at least one field to export');
      return;
    }
    setExporting(true);
    setTimeout(() => {
      setExporting(false);
      if (onExport) {
        onExport(format, { from: dateFrom, to: dateTo }, Array.from(selectedFields));
      } else {
        toast.success(`${format.toUpperCase()} export ready`, {
          description: `${selectedFields.size} fields · ${dateFrom} → ${dateTo}`,
        });
      }
      onClose();
    }, 900);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />

      {/* Modal */}
      <div className="relative bg-card border border-border rounded-xl shadow-2xl w-full max-w-md fade-in">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <Download size={16} className="text-primary" />
            <h2 className="text-sm font-semibold">Export {title}</h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            <X size={15} />
          </button>
        </div>

        <div className="p-5 space-y-5">
          {/* Format selector */}
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Export Format</p>
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => setFormat('csv')}
                className={`flex items-center gap-2.5 px-3 py-2.5 rounded-lg border text-sm font-medium transition-all ${
                  format === 'csv' ?'bg-primary/10 border-primary/40 text-primary' :'bg-muted/30 border-border text-muted-foreground hover:text-foreground hover:border-border/80'
                }`}
              >
                <FileSpreadsheet size={16} />
                CSV
              </button>
              <button
                onClick={() => setFormat('pdf')}
                className={`flex items-center gap-2.5 px-3 py-2.5 rounded-lg border text-sm font-medium transition-all ${
                  format === 'pdf' ?'bg-primary/10 border-primary/40 text-primary' :'bg-muted/30 border-border text-muted-foreground hover:text-foreground hover:border-border/80'
                }`}
              >
                <FileText size={16} />
                PDF
              </button>
            </div>
          </div>

          {/* Date range */}
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Date Range</p>
            {/* Presets */}
            <div className="flex flex-wrap gap-1.5 mb-3">
              {PRESETS.map((p) => (
                <button
                  key={p.label}
                  onClick={() => applyPreset(p.days)}
                  className="px-2.5 py-1 text-[11px] font-medium rounded-full bg-muted/40 border border-border text-muted-foreground hover:text-foreground hover:border-primary/30 transition-colors"
                >
                  {p.label}
                </button>
              ))}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-[11px] text-muted-foreground mb-1 block">From</label>
                <div className="relative">
                  <Calendar size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="date"
                    value={dateFrom}
                    max={dateTo}
                    onChange={(e) => setDateFrom(e.target.value)}
                    className="w-full pl-7 pr-2 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                  />
                </div>
              </div>
              <div>
                <label className="text-[11px] text-muted-foreground mb-1 block">To</label>
                <div className="relative">
                  <Calendar size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="date"
                    value={dateTo}
                    min={dateFrom}
                    max={todayStr()}
                    onChange={(e) => setDateTo(e.target.value)}
                    className="w-full pl-7 pr-2 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                  />
                </div>
              </div>
            </div>
          </div>

          {/* Field selection */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Fields</p>
              <div className="flex items-center gap-2">
                <button onClick={selectAll} className="text-[11px] text-primary hover:text-primary/80 transition-colors">All</button>
                <span className="text-muted-foreground/40">·</span>
                <button onClick={clearAll} className="text-[11px] text-muted-foreground hover:text-foreground transition-colors">None</button>
                <span className="text-[11px] text-muted-foreground">({selectedFields.size}/{fields.length})</span>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-1.5 max-h-40 overflow-y-auto scrollbar-thin pr-1">
              {fields.map((field) => (
                <label
                  key={field.key}
                  className="flex items-center gap-2 px-2.5 py-1.5 rounded-md bg-muted/30 border border-border cursor-pointer hover:bg-muted/50 transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={selectedFields.has(field.key)}
                    onChange={() => toggleField(field.key)}
                    className="w-3 h-3 accent-primary"
                  />
                  <span className="text-xs text-foreground truncate">{field.label}</span>
                </label>
              ))}
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-5 py-4 border-t border-border">
          <p className="text-[11px] text-muted-foreground">
            {selectedFields.size} field{selectedFields.size !== 1 ? 's' : ''} selected
          </p>
          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleExport}
              disabled={exporting || selectedFields.size === 0}
              className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {exporting ? (
                <>
                  <div className="w-3 h-3 border border-primary-foreground/40 border-t-primary-foreground rounded-full animate-spin" />
                  Exporting…
                </>
              ) : (
                <>
                  <Download size={12} />
                  Export {format.toUpperCase()}
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

