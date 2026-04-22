'use client';
import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Monitor, Terminal, Activity, Shield, Clock, Cpu, HardDrive, Wifi, ChevronRight, ArrowLeft, Play, CheckCircle, XCircle, AlertTriangle, RefreshCw, ScrollText, Search, ChevronDown, ChevronUp, Download, RotateCcw, Layers, Globe, Lock, Users, Power, Camera, Folder, File, List, Network, Database, Server, Wrench, BarChart2, Calendar, Clipboard, Volume2, Monitor as DisplayIcon, Package, Rocket, Hash, Info, X, Send, Radio, Loader2 } from 'lucide-react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import StatusBadge from '@/components/ui/StatusBadge';
import CommandResultPresentation from '@/components/results/CommandResultPresentation';
import DeviceAppLockQuickPanel from './DeviceAppLockQuickPanel';
import { useAuth } from '@/contexts/AuthContext';
import { formatLocalDateTime, formatLocalTime } from '@/lib/dateTime';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import {
  mapCommandListRow,
  mergeCommandDetail,
  type CommandDetailApi,
  type NormalizedCommandResult,
} from '@/lib/commandResults';
import { parseKernelTelemetryEvent, telemetryMaskedFields, telemetryPercent, telemetryText } from '@/lib/telemetry';
import { toast } from 'sonner';

// ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Types ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬
type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';
type CommandState = 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';
type CommandBlockReason = 'unknown_command' | 'not_supported_runtime';

interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: 'compliant' | 'non_compliant' | 'drift';
  lastSeen: string;
  agentVersion: string;
  policySync: boolean | null;
  kernelGuard: boolean | null;
  ipAddress: string;
  sessionId: string | null;
  cpu: string;
  ram: string;
  disk: string;
  uptime: string;
  location: string;
  department: string;
}

interface CommandEntry {
  id: string;
  method: string;
  params: Record<string, unknown>;
  state: CommandState;
  actor: string;
  queuedAt: string;
  completedAt: string | null;
  duration: string | null;
  resultPreview: string | null;
}

interface TraceStep {
  label: string;
  detail: string;
  status: 'done' | 'active' | 'pending' | 'error';
  time: string | null;
}

interface DeviceDetailApi {
  device_id: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  last_seen?: string | null;
  agent_version?: string | null;
  os_build?: string | null;
  risk_score?: number | string | null;
  policy_in_sync?: boolean | null;
  compliance?: { status?: string | null };
  resolved_os_build?: string | null;
  resolved_presence_state?: string | null;
  resolved_connection_mode?: string | null;
  resolved_compliance_status?: string | null;
  resolved_policy_in_sync?: boolean | null;
  kernel_guard?: boolean | null;
  telemetry_latest?: {
    cpu?: number | null;
    ram?: number | null;
    disk_usage?: number | null;
    risk_score?: number | string | null;
  } | null;
}

interface CommandsApiResponse {
  commands?: Array<{
    command_id?: string;
    device_id?: string;
    device_name?: string | null;
    method?: string;
    params?: Record<string, unknown> | null;
    state?: CommandState;
    execution_state?: string | null;
    queued_at?: string | null;
    dispatched_at?: string | null;
    completed_at?: string | null;
    trace_id?: string | null;
    result?: {
      status?: string | null;
      notes?: string | null;
      artifact_url?: string | null;
      artifact_checksum?: string | null;
      data?: unknown;
      output_text?: string | null;
      meta?: Record<string, unknown> | null;
    } | null;
    result_status?: string | null;
    result_notes?: string | null;
    artifact_url?: string | null;
    artifact_checksum?: string | null;
    error_code?: number | null;
    error_message?: string | null;
    reason?: string | null;
    actor_email?: string | null;
  }>;
}

interface CommandCapabilitiesResponse {
  canonical_methods?: string[];
  runtime_supported_methods?: string[];
  rejection_reasons?: Record<string, string>;
}

interface CommandDetailApiResponse {
  command_id?: string;
  device_id?: string;
  device_name?: string | null;
  method?: string;
  params?: Record<string, unknown> | null;
  state?: CommandState;
  execution_state?: string | null;
  queued_at?: string | null;
  dispatched_at?: string | null;
  completed_at?: string | null;
  trace_id?: string | null;
  actor_email?: string | null;
  result?: {
    status?: string | null;
    notes?: string | null;
    artifact_url?: string | null;
    artifact_checksum?: string | null;
    data?: unknown;
    output_text?: string | null;
    meta?: Record<string, unknown> | null;
  } | null;
  result_status?: string | null;
  result_notes?: string | null;
  artifact_url?: string | null;
  artifact_checksum?: string | null;
  error_code?: number | null;
  error_message?: string | null;
  reason?: string | null;
}

interface TelemetryApiResponse {
  schema_version?: string | null;
  session_id?: string | null;
  seq?: number | string | null;
  timestamp?: string | null;
  telemetry_scope?: string | null;
  policy_hash?: string | null;
  masked_fields?: unknown[];
  presence_state?: string | null;
  connection_mode?: string | null;
  resolved_os_build?: string | null;
  resolved_presence_state?: string | null;
  resolved_connection_mode?: string | null;
  resolved_compliance_status?: string | null;
  resolved_policy_in_sync?: boolean | null;
  metrics?: {
    cpu?: number | null;
    ram?: number | null;
    disk_usage?: number | null;
    network_tx?: number | null;
    network_rx?: number | null;
    risk_score?: number | null;
    battery_pct?: number | null;
    os_build?: string | null;
    os_version?: string | null;
    agent_version?: string | null;
    policy_in_sync?: boolean | string | null;
    compliance_status?: string | null;
    patch_level?: string | null;
    geo_hash?: string | null;
  };
}

interface TelemetryHistoryApiResponse {
  points?: Array<{
    timestamp?: string | null;
    metrics?: {
      kernel_event?: Record<string, unknown> | null;
    };
  }>;
}

interface DeviceKernelEvent {
  id: string;
  category: string;
  opcode: string;
  status: string;
  errorCode: number;
  durationMs: number;
  queueDepth: number;
  timestamp: string;
}

interface AlertsApiResponse {
  alerts?: Array<{
    alert_id?: string;
    device_id?: string;
    severity?: string;
    message?: string;
    timestamp?: string | null;
    acknowledged?: boolean;
  }>;
}

interface AuditApiResponse {
  entries?: Array<{
    id?: string;
    timestamp?: string | null;
    event_type?: string;
    summary?: string;
  }>;
}

interface DeviceAlert {
  id: string;
  severity: string;
  message: string;
  time: string;
  status: string;
}

interface DeviceAuditEntry {
  id: string;
  type: string;
  actor: string;
  action: string;
  time: string;
  outcome: 'success' | 'failure';
}

interface DeviceTelemetry {
  cpu: number | null;
  ram: number | null;
  disk_usage: number | null;
  network_tx: number | null;
  network_rx: number | null;
  risk_score: number | null;
  battery_pct: number | null;
  policy_in_sync: boolean | null;
  compliance_status: string | null;
  os_build: string | null;
  os_version: string | null;
  agent_version: string | null;
  patch_level: string | null;
  geo_hash: string | null;
  schema_version: string | null;
  session_id: string | null;
  seq: number | string | null;
  telemetry_scope: string | null;
  policy_hash: string | null;
  masked_fields: unknown[];
  presence_state: string | null;
  connection_mode: string | null;
  timestamp: string | null;
}

// ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Command Library ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬
const COMMAND_CATEGORIES = [
  {
    category: 'System',
    icon: Server,
    color: 'text-blue-400',
    commands: [
      { id: 'system-info', label: 'System Info', desc: 'Full OS, hardware, and agent info', icon: Info, risk: 'low' },
      { id: 'hardware-info', label: 'Hardware Info', desc: 'CPU, RAM, GPU, motherboard details', icon: Cpu, risk: 'low' },
      { id: 'performance-metrics', label: 'Performance Metrics', desc: 'Real-time CPU, RAM, disk, network usage', icon: BarChart2, risk: 'low' },
      { id: 'uptime', label: 'Uptime', desc: 'System uptime and boot time', icon: Clock, risk: 'low' },
    ],
  },
  {
    category: 'Screen & Display',
    icon: DisplayIcon,
    color: 'text-purple-400',
    commands: [
      { id: 'screenshot-capture', label: 'Screenshot', desc: 'Capture current screen state', icon: Camera, risk: 'medium' },
      { id: 'display-info', label: 'Display Info', desc: 'Monitor resolution, refresh rate, DPI', icon: DisplayIcon, risk: 'low' },
      { id: 'lock_screen', label: 'Lock Screen', desc: 'Immediately lock the workstation', icon: Lock, risk: 'high' },
    ],
  },
  {
    category: 'Filesystem',
    icon: Folder,
    color: 'text-amber-400',
    commands: [
      { id: 'filesystem', label: 'Browse Filesystem', desc: 'Interactive file tree explorer', icon: Folder, risk: 'low' },
      { id: 'download-file', label: 'Download File', desc: 'Retrieve a file from the device', icon: Download, risk: 'medium' },
      { id: 'upload-file', label: 'Upload File', desc: 'Push a file to the device', icon: Send, risk: 'high' },
      { id: 'create-file', label: 'Create File', desc: 'Create a new file at a path', icon: File, risk: 'high' },
      { id: 'create-folder', label: 'Create Folder', desc: 'Create a new directory', icon: Folder, risk: 'high' },
      { id: 'delete-file', label: 'Delete File', desc: 'Remove a file from the device', icon: X, risk: 'high' },
      { id: 'delete-folder', label: 'Delete Folder', desc: 'Remove a directory recursively', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Processes',
    icon: Layers,
    color: 'text-green-400',
    commands: [
      { id: 'process-list', label: 'Process List', desc: 'All running processes with CPU/RAM', icon: List, risk: 'low' },
      { id: 'kill-process', label: 'Kill Process', desc: 'Terminate a process by PID or name', icon: X, risk: 'high' },
      { id: 'start-process', label: 'Start Process', desc: 'Launch an executable on the device', icon: Play, risk: 'high' },
    ],
  },
  {
    category: 'Network',
    icon: Network,
    color: 'text-cyan-400',
    commands: [
      { id: 'network-info', label: 'Network Info', desc: 'Interfaces, IPs, DNS, gateway', icon: Network, risk: 'low' },
      { id: 'ping', label: 'Ping', desc: 'Connectivity check to the agent', icon: Radio, risk: 'low' },
      { id: 'netstat', label: 'Netstat', desc: 'Active connections and listening ports', icon: Globe, risk: 'low' },
      { id: 'dns-lookup', label: 'DNS Lookup', desc: 'Resolve a hostname from the device', icon: Globe, risk: 'low' },
    ],
  },
  {
    category: 'Registry',
    icon: Database,
    color: 'text-orange-400',
    commands: [
      { id: 'registry-read', label: 'Registry Read', desc: 'Read a registry key value', icon: Database, risk: 'medium' },
      { id: 'registry-write', label: 'Registry Write', desc: 'Write a value to the registry', icon: Database, risk: 'high' },
      { id: 'registry-delete', label: 'Registry Delete', desc: 'Delete a registry key', icon: Database, risk: 'high' },
    ],
  },
  {
    category: 'Services',
    icon: Wrench,
    color: 'text-indigo-400',
    commands: [
      { id: 'services-list', label: 'Services List', desc: 'All Windows services and their states', icon: List, risk: 'low' },
      { id: 'service-start', label: 'Start Service', desc: 'Start a stopped Windows service', icon: Play, risk: 'high' },
      { id: 'service-stop', label: 'Stop Service', desc: 'Stop a running Windows service', icon: X, risk: 'high' },
      { id: 'service-restart', label: 'Restart Service', desc: 'Restart a Windows service', icon: RotateCcw, risk: 'high' },
    ],
  },
  {
    category: 'Event Logs',
    icon: ScrollText,
    color: 'text-rose-400',
    commands: [
      { id: 'event-logs', label: 'Event Logs', desc: 'Windows event log entries', icon: ScrollText, risk: 'low' },
      { id: 'security-logs', label: 'Security Logs', desc: 'Security audit log entries', icon: Shield, risk: 'low' },
      { id: 'application-logs', label: 'Application Logs', desc: 'Application event log entries', icon: ScrollText, risk: 'low' },
    ],
  },
  {
    category: 'Scheduled Tasks',
    icon: Calendar,
    color: 'text-teal-400',
    commands: [
      { id: 'scheduled-tasks', label: 'Scheduled Tasks', desc: 'All Windows scheduled tasks', icon: Calendar, risk: 'low' },
      { id: 'create-task', label: 'Create Task', desc: 'Create a new scheduled task', icon: Calendar, risk: 'high' },
      { id: 'delete-task', label: 'Delete Task', desc: 'Remove a scheduled task', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Users & Sessions',
    icon: Users,
    color: 'text-pink-400',
    commands: [
      { id: 'users-list', label: 'Users List', desc: 'Local and domain user accounts', icon: Users, risk: 'low' },
      { id: 'active-sessions', label: 'Active Sessions', desc: 'Currently logged-in users', icon: Users, risk: 'low' },
      { id: 'logout_user', label: 'Log Off User', desc: 'Force log off a user session', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Power',
    icon: Power,
    color: 'text-yellow-400',
    commands: [
      { id: 'power-info', label: 'Power Info', desc: 'Battery, power plan, sleep settings', icon: Power, risk: 'low' },
      { id: 'shutdown_device', label: 'Shutdown', desc: 'Gracefully shut down the device', icon: Power, risk: 'critical' },
      { id: 'reboot_device', label: 'Reboot', desc: 'Restart the device', icon: RotateCcw, risk: 'critical' },
      { id: 'sleep', label: 'Sleep', desc: 'Put the device to sleep', icon: Power, risk: 'high' },
    ],
  },
  {
    category: 'Clipboard & Audio',
    icon: Clipboard,
    color: 'text-lime-400',
    commands: [
      { id: 'clipboard-read', label: 'Read Clipboard', desc: 'Get current clipboard contents', icon: Clipboard, risk: 'medium' },
      { id: 'clipboard-write', label: 'Write Clipboard', desc: 'Set clipboard contents', icon: Clipboard, risk: 'medium' },
      { id: 'audio-info', label: 'Audio Info', desc: 'Audio devices and volume levels', icon: Volume2, risk: 'low' },
      { id: 'set-volume', label: 'Set Volume', desc: 'Adjust system volume level', icon: Volume2, risk: 'medium' },
    ],
  },
  {
    category: 'Software',
    icon: Package,
    color: 'text-violet-400',
    commands: [
      { id: 'installed-apps', label: 'Installed Apps', desc: 'All installed applications', icon: Package, risk: 'low' },
      { id: 'startup-items', label: 'Startup Items', desc: 'Programs that run at startup', icon: Rocket, risk: 'low' },
      { id: 'uninstall-app', label: 'Uninstall App', desc: 'Remove an installed application', icon: X, risk: 'high' },
    ],
  },
];

function normalizeStatus(value: string | null | undefined): DeviceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'active' || normalized === 'online') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded') return 'degraded';
  return 'offline';
}

function normalizeCompliance(value: string | null | undefined): ComplianceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift' || normalized === 'unknown' || normalized === 'degraded') return 'drift';
  return 'non_compliant';
}

function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

function formatTime(iso: string | null | undefined): string {
  return formatLocalTime(iso, '-');
}

function formatDateTime(iso: string | null | undefined): string {
  return formatLocalDateTime(iso, '-');
}

function formatDuration(startIso: string | null | undefined, endIso: string | null | undefined): string | null {
  if (!startIso || !endIso) return null;
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return null;
  return `${Math.round((end - start) / 1000)}s`;
}

function parseJsonParams(input: string): { ok: true; value: Record<string, unknown> } | { ok: false; error: string } {
  const trimmed = input.trim();
  if (!trimmed) {
    return { ok: true, value: {} };
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
      return { ok: false, error: 'Parameters must be a JSON object.' };
    }

    return { ok: true, value: parsed as Record<string, unknown> };
  } catch {
    return { ok: false, error: 'Invalid JSON parameters.' };
  }
}

function isTerminalState(state: CommandState): boolean {
  return ['completed', 'failed', 'expired', 'rejected'].includes(state);
}

function hasRenderableResult(row: NormalizedCommandResult): boolean {
  if (row.result && Object.keys(row.result).length > 0) {
    return true;
  }

  return Boolean(
    row.resultStatus ||
    row.resultNotes ||
    row.artifactUrl ||
    row.artifactChecksum ||
    row.errorCode != null ||
    row.errorMessage ||
    row.reason,
  );
}

function parseTelemetryBoolean(value: unknown): boolean | null {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
  }
  return null;
}

function reasonToText(reason: string): string {
  if (reason === 'unknown_command') {
    return 'Non-canonical command id';
  }
  if (reason === 'not_supported_runtime') {
    return 'Not supported by current runtime';
  }
  return reason;
}

function getFallbackDevice(id: string): Device {
  return {
    id,
    hostname: id,
    osBuild: '-',
    owner: 'Unknown',
    status: 'offline',
    riskScore: 0,
    compliance: 'drift',
    lastSeen: '-',
    agentVersion: '-',
    policySync: null,
    kernelGuard: null,
    ipAddress: '-',
    sessionId: null,
    cpu: 'Unknown',
    ram: 'Unknown',
    disk: 'Unknown',
    uptime: 'Unknown',
    location: 'Unknown',
    department: 'Unknown',
  };
}
const buildTraceSteps = (method: string, state: CommandState): TraceStep[] => {
  const steps: TraceStep[] = [
    { label: 'Web UI', detail: 'Command submitted via control plane', status: 'done', time: '21:06:01' },
    { label: 'Laravel API', detail: 'Validated, authorized, signed payload', status: 'done', time: '21:06:01' },
    { label: 'FastAPI Gateway', detail: 'Signature verified, dispatched to agent channel', status: state === 'queued' ? 'pending' : 'done', time: state === 'queued' ? null : '21:06:02' },
    { label: 'Windows Agent', detail: `Executing: ${method}`, status: ['queued', 'dispatched'].includes(state) ? 'pending' : state === 'executing' ? 'active' : state === 'failed' ? 'error' : 'done', time: ['queued', 'dispatched'].includes(state) ? null : '21:06:03' },
    { label: 'Result Return', detail: 'Agent -> FastAPI -> Laravel -> UI', status: ['queued', 'dispatched', 'ack_received', 'executing'].includes(state) ? 'pending' : state === 'failed' ? 'error' : 'done', time: ['queued', 'dispatched', 'ack_received', 'executing'].includes(state) ? null : '21:06:09' },
  ];
  return steps;
};

const MAIN_TABS = ['Overview', 'Commands', 'Trace', 'Results', 'History', 'Telemetry', 'Alerts', 'Audit'];

export default function DeviceDetailPageContent() {
  const { user } = useAuth();
  const searchParams = useSearchParams();
  const deviceId = searchParams.get('device') ?? 'WKSTN-055';
  const canViewAlerts = user?.role ? user.role !== 'viewer' : false;
  const mainTabs = useMemo(
    () => (canViewAlerts ? MAIN_TABS : MAIN_TABS.filter((tab) => tab !== 'Alerts')),
    [canViewAlerts],
  );
  const [device, setDevice] = useState<Device>(() => getFallbackDevice(deviceId));
  const [isLoadingDevice, setIsLoadingDevice] = useState(true);
  const [commandHistory, setCommandHistory] = useState<CommandEntry[]>([]);
  const [recentResults, setRecentResults] = useState<NormalizedCommandResult[]>([]);
  const [alerts, setAlerts] = useState<DeviceAlert[]>([]);
  const [auditEntries, setAuditEntries] = useState<DeviceAuditEntry[]>([]);
  const [telemetry, setTelemetry] = useState<DeviceTelemetry>({
    cpu: null,
    ram: null,
    disk_usage: null,
    network_tx: null,
    network_rx: null,
    risk_score: null,
    battery_pct: null,
    policy_in_sync: null,
    compliance_status: null,
    os_build: null,
    os_version: null,
    agent_version: null,
    patch_level: null,
    geo_hash: null,
    schema_version: null,
    session_id: null,
    seq: null,
    telemetry_scope: null,
    policy_hash: null,
    masked_fields: [],
    presence_state: null,
    connection_mode: null,
    timestamp: null,
  });
  const [kernelEvents, setKernelEvents] = useState<DeviceKernelEvent[]>([]);

  const [activeTab, setActiveTab] = useState('Overview');
  const [commandSearch, setCommandSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [activeCommand, setActiveCommand] = useState<{ id: string; label: string; risk: string } | null>(null);
  const [commandParams, setCommandParams] = useState('');
  const [isDispatching, setIsDispatching] = useState(false);
  const [liveResults, setLiveResults] = useState<{ commandId: string; method: string; state: CommandState; output: string; traceSteps: TraceStep[] } | null>(null);
  const [expandedHistoryId, setExpandedHistoryId] = useState<string | null>(null);
  const [commandCapabilities, setCommandCapabilities] = useState<CommandCapabilitiesResponse>({
    canonical_methods: [],
    runtime_supported_methods: [],
    rejection_reasons: {},
  });
  const liveRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!canViewAlerts && activeTab === 'Alerts') {
      setActiveTab('Overview');
    }
  }, [activeTab, canViewAlerts]);

  const loadDeviceData = useCallback(async (mode: 'interactive' | 'silent' = 'interactive') => {
    const showToasts = mode === 'interactive';
    if (mode === 'interactive') {
      setIsLoadingDevice(true);
    }

    const encodedId = encodeURIComponent(deviceId);
    const from = new Date(Date.now() - (24 * 60 * 60 * 1000)).toISOString();
    const to = new Date().toISOString();
    const alertsRequest = canViewAlerts
      ? fetch('/api/alerts?limit=100', { credentials: 'include', cache: 'no-store' })
      : Promise.resolve(new Response(JSON.stringify({ alerts: [] }), { status: 200 }));

    const [deviceRes, commandsRes, telemetryRes, telemetryHistoryRes, alertsRes, auditRes, capabilitiesRes] = await Promise.allSettled([
      fetch(`/api/devices/${encodedId}`, { credentials: 'include', cache: 'no-store' }),
      fetch(`/api/devices/${encodedId}/commands?limit=20`, { credentials: 'include', cache: 'no-store' }),
      fetch(`/api/telemetry/devices/${encodedId}/latest`, { credentials: 'include', cache: 'no-store' }),
      fetch(`/api/telemetry/devices/${encodedId}/history?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}&bucket=raw`, { credentials: 'include', cache: 'no-store' }),
      alertsRequest,
      fetch(`/api/audit/device/${encodedId}?limit=100`, { credentials: 'include', cache: 'no-store' }),
      fetch(`/api/commands/capabilities?device_id=${encodedId}`, { credentials: 'include', cache: 'no-store' }),
    ]);

    if (deviceRes.status === 'fulfilled' && deviceRes.value.ok) {
      const payload = (await deviceRes.value.json()) as DeviceDetailApi;
      const detailTelemetry = payload.telemetry_latest ?? {};
      const resolvedOsBuild = payload.resolved_os_build?.trim();
      const resolvedCompliance = payload.resolved_compliance_status?.trim();
      const resolvedPresence = payload.resolved_presence_state?.trim();
      const resolvedPolicySync = typeof payload.resolved_policy_in_sync === 'boolean' ? payload.resolved_policy_in_sync : null;

      setDevice({
        id: payload.device_id,
        hostname: payload.device_name?.trim() || payload.device_id,
        osBuild: resolvedOsBuild || payload.os_build?.trim() || '-',
        owner: payload.owner_email?.trim() || 'Unknown',
        status: normalizeStatus(resolvedPresence || payload.lifecycle_state),
        riskScore: normalizeRisk(payload.risk_score ?? detailTelemetry.risk_score),
        compliance: normalizeCompliance(resolvedCompliance || payload.compliance?.status),
        lastSeen: formatDateTime(payload.last_seen),
        agentVersion: payload.agent_version?.trim() || '-',
        policySync: resolvedPolicySync ?? (typeof payload.policy_in_sync === 'boolean' ? payload.policy_in_sync : null),
        kernelGuard: typeof payload.kernel_guard === 'boolean' ? payload.kernel_guard : null,
        ipAddress: '-',
        sessionId: null,
        cpu: detailTelemetry.cpu == null ? 'Unknown' : `${detailTelemetry.cpu}%`,
        ram: detailTelemetry.ram == null ? 'Unknown' : `${detailTelemetry.ram}%`,
        disk: detailTelemetry.disk_usage == null ? 'Unknown' : `${detailTelemetry.disk_usage}%`,
        uptime: 'Unknown',
        location: 'Unknown',
        department: 'Unknown',
      });
    } else {
      setDevice(getFallbackDevice(deviceId));
      if (showToasts) {
        toast.error('Could not load device detail');
      }
    }

    if (commandsRes.status === 'fulfilled' && commandsRes.value.ok) {
      const payload = (await commandsRes.value.json()) as CommandsApiResponse;
      const normalizedRows = (payload.commands ?? []).map((cmd) => mapCommandListRow(cmd));
      const hydratedRows = [...normalizedRows];
      const latest = hydratedRows[0];

      if (latest && isTerminalState(latest.state) && !hasRenderableResult(latest)) {
        try {
          const detailResponse = await fetch(`/api/commands/${encodeURIComponent(latest.commandId)}`, {
            credentials: 'include',
            cache: 'no-store',
          });
          if (detailResponse.ok) {
            const detailPayload = (await detailResponse.json()) as CommandDetailApi;
            hydratedRows[0] = mergeCommandDetail(latest, detailPayload);
          }
        } catch (detailError) {
          console.warn('device-detail latest command hydration failed', detailError);
        }
      }

      setRecentResults(hydratedRows);
      setCommandHistory(
        hydratedRows.map((cmd) => ({
          id: cmd.commandId,
          method: cmd.method,
          params: cmd.params,
          state: cmd.state,
          actor: cmd.actorEmail,
          queuedAt: formatTime(cmd.queuedAt),
          completedAt: cmd.completedAt ? formatTime(cmd.completedAt) : null,
          duration: formatDuration(cmd.queuedAt, cmd.completedAt),
          resultPreview:
            cmd.errorMessage ||
            cmd.reason ||
            cmd.resultNotes ||
            cmd.resultStatus ||
            (cmd.errorCode != null ? `error ${cmd.errorCode}` : null),
        })),
      );
    } else {
      setCommandHistory([]);
      setRecentResults([]);
    }

    if (telemetryRes.status === 'fulfilled' && telemetryRes.value.ok) {
      const payload = (await telemetryRes.value.json()) as TelemetryApiResponse;
      setTelemetry({
        cpu: payload.metrics?.cpu ?? null,
        ram: payload.metrics?.ram ?? null,
        disk_usage: payload.metrics?.disk_usage ?? null,
        network_tx: payload.metrics?.network_tx ?? null,
        network_rx: payload.metrics?.network_rx ?? null,
        risk_score: payload.metrics?.risk_score ?? null,
        battery_pct: payload.metrics?.battery_pct ?? null,
        policy_in_sync: parseTelemetryBoolean(payload.metrics?.policy_in_sync) ?? (typeof payload.resolved_policy_in_sync === 'boolean' ? payload.resolved_policy_in_sync : null),
        compliance_status: payload.metrics?.compliance_status ?? payload.resolved_compliance_status ?? null,
        os_build: payload.metrics?.os_build ?? payload.resolved_os_build ?? null,
        os_version: payload.metrics?.os_version ?? null,
        agent_version: payload.metrics?.agent_version ?? null,
        patch_level: payload.metrics?.patch_level ?? null,
        geo_hash: payload.metrics?.geo_hash ?? null,
        schema_version: payload.schema_version ?? null,
        session_id: payload.session_id ?? null,
        seq: payload.seq ?? null,
        telemetry_scope: payload.telemetry_scope ?? null,
        policy_hash: payload.policy_hash ?? null,
        masked_fields: Array.isArray(payload.masked_fields) ? payload.masked_fields : [],
        presence_state: payload.resolved_presence_state ?? payload.presence_state ?? null,
        connection_mode: payload.resolved_connection_mode ?? payload.connection_mode ?? null,
        timestamp: payload.timestamp ?? null,
      });
    } else {
      setTelemetry({
        cpu: null,
        ram: null,
        disk_usage: null,
        network_tx: null,
        network_rx: null,
        risk_score: null,
        battery_pct: null,
        policy_in_sync: null,
        compliance_status: null,
        os_build: null,
        os_version: null,
        agent_version: null,
        patch_level: null,
        geo_hash: null,
        schema_version: null,
        session_id: null,
        seq: null,
        telemetry_scope: null,
        policy_hash: null,
        masked_fields: [],
        presence_state: null,
        connection_mode: null,
        timestamp: null,
      });
    }

    if (telemetryHistoryRes.status === 'fulfilled' && telemetryHistoryRes.value.ok) {
      const payload = (await telemetryHistoryRes.value.json()) as TelemetryHistoryApiResponse;
      const rows = (payload.points ?? [])
        .map((point) => {
          const timestamp = point.timestamp ?? null;
          const kernelEventRaw = point.metrics?.kernel_event ?? null;
          if (!timestamp || !kernelEventRaw) return null;

          const parsed = parseKernelTelemetryEvent(kernelEventRaw);
          if (!parsed) return null;

          return {
            id: `${parsed.eventId}-${timestamp}`,
            category: parsed.category,
            opcode: parsed.opcode,
            status: parsed.status,
            errorCode: parsed.errorCode,
            durationMs: parsed.durationMs,
            queueDepth: parsed.queueDepth,
            timestamp,
          } satisfies DeviceKernelEvent;
        })
        .filter(Boolean) as DeviceKernelEvent[];

      rows.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
      setKernelEvents(rows.slice(0, 10));
    } else {
      setKernelEvents([]);
    }

    if (!canViewAlerts) {
      setAlerts([]);
    } else if (alertsRes.status === 'fulfilled' && alertsRes.value.ok) {
      const payload = (await alertsRes.value.json()) as AlertsApiResponse;
      setAlerts(
        (payload.alerts ?? [])
          .filter((item) => item.device_id === deviceId)
          .map((item) => ({
            id: item.alert_id ?? 'unknown',
            severity: (item.severity ?? 'low').toLowerCase(),
            message: item.message ?? 'No message',
            time: formatTime(item.timestamp),
            status: item.acknowledged ? 'acknowledged' : 'open',
          })),
      );
    } else {
      setAlerts([]);
    }

    if (auditRes.status === 'fulfilled' && auditRes.value.ok) {
      const payload = (await auditRes.value.json()) as AuditApiResponse;
      setAuditEntries(
        (payload.entries ?? []).map((entry) => ({
          id: entry.id ?? 'unknown',
          type: entry.event_type ?? 'event',
          actor: 'system',
          action: entry.summary ?? `${entry.event_type ?? 'event'} event`,
          time: formatTime(entry.timestamp),
          outcome: 'success' as const,
        })),
      );
    } else {
      setAuditEntries([]);
    }

    if (capabilitiesRes.status === 'fulfilled' && capabilitiesRes.value.ok) {
      const payload = (await capabilitiesRes.value.json()) as CommandCapabilitiesResponse;
      setCommandCapabilities({
        canonical_methods: payload.canonical_methods ?? [],
        runtime_supported_methods: payload.runtime_supported_methods ?? [],
        rejection_reasons: payload.rejection_reasons ?? {},
      });
    } else {
      setCommandCapabilities({
        canonical_methods: [],
        runtime_supported_methods: [],
        rejection_reasons: {},
      });
      if (showToasts) {
        toast.error('Command capabilities unavailable');
      }
    }

    if (mode === 'interactive') {
      setIsLoadingDevice(false);
    }
  }, [canViewAlerts, deviceId]);

  useEffect(() => {
    void loadDeviceData();
  }, [loadDeviceData]);

  useEffect(() => {
    let intervalId: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
      const pollMs = document.visibilityState === 'visible' ? 5000 : 30000;
      intervalId = setInterval(() => {
        void loadDeviceData('silent');
      }, pollMs);
    };

    startPolling();
    const handleVisibility = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [loadDeviceData]);
  const riskColor = device.riskScore > 0.6 ? 'text-red-400' : device.riskScore > 0.3 ? 'text-amber-400' : 'text-green-400';

  const telemetryCards = useMemo(
    () => [
      { label: 'CPU Usage', value: telemetry.cpu, color: 'bg-green-500', icon: Cpu },
      { label: 'RAM Usage', value: telemetry.ram, color: 'bg-blue-500', icon: Activity },
      { label: 'Disk Usage', value: telemetry.disk_usage, color: 'bg-amber-500', icon: HardDrive },
      { label: 'Network TX', value: telemetry.network_tx, color: 'bg-cyan-500', icon: Wifi },
      { label: 'Network RX', value: telemetry.network_rx, color: 'bg-violet-500', icon: Wifi },
      { label: 'Risk Score', value: telemetry.risk_score, color: 'bg-pink-500', icon: BarChart2 },
    ],
    [telemetry],
  );

  const telemetryMetaRows = useMemo(
    () => [
      { label: 'Schema', value: telemetryText(telemetry.schema_version, 'Unknown') },
      { label: 'Session', value: telemetryText(telemetry.session_id, 'Unknown') },
      { label: 'Seq', value: telemetryText(telemetry.seq, 'Unknown') },
      { label: 'Scope', value: telemetryText(telemetry.telemetry_scope, 'Unknown') },
      { label: 'Policy Hash', value: telemetryText(telemetry.policy_hash, 'Unknown') },
      { label: 'Masked Fields', value: telemetryMaskedFields(telemetry.masked_fields) },
      { label: 'Presence', value: telemetryText(telemetry.presence_state, 'Unknown') },
      { label: 'Connection', value: telemetryText(telemetry.connection_mode, 'Unknown') },
      { label: 'Policy Sync', value: telemetry.policy_in_sync == null ? 'Unknown' : telemetry.policy_in_sync ? 'Synchronized' : 'Mismatch' },
      { label: 'Compliance', value: telemetryText(telemetry.compliance_status, 'Unknown').replace('_', ' ') },
      { label: 'Battery', value: telemetryPercent(telemetry.battery_pct, 'No data available') },
      { label: 'Agent Version', value: telemetryText(telemetry.agent_version, 'Unknown') },
      { label: 'OS Build', value: telemetryText(telemetry.os_build, 'Unknown') },
      { label: 'OS Version', value: telemetryText(telemetry.os_version, 'Unknown') },
      { label: 'Patch Level', value: telemetryText(telemetry.patch_level, 'Unknown') },
      { label: 'Geo Hash', value: telemetryText(telemetry.geo_hash, 'Unknown') },
    ],
    [telemetry],
  );

  const kernelTelemetrySummary = useMemo(() => {
    if (kernelEvents.length === 0) {
      return {
        total: 0,
        errorRate: null as number | null,
        avgLatency: null as number | null,
        queueDepth: null as number | null,
      };
    }

    const failures = kernelEvents.filter((event) => event.status !== 'ok' || event.errorCode > 0).length;
    const avgLatency = kernelEvents.reduce((sum, event) => sum + event.durationMs, 0) / kernelEvents.length;
    const queueDepth = Math.max(...kernelEvents.map((event) => event.queueDepth));

    return {
      total: kernelEvents.length,
      errorRate: (failures / kernelEvents.length) * 100,
      avgLatency,
      queueDepth,
    };
  }, [kernelEvents]);

  const filteredCategories = useMemo(
    () =>
      COMMAND_CATEGORIES.map((cat) => ({
        ...cat,
        commands: cat.commands.filter(
          (cmd) =>
            !commandSearch ||
            cmd.label.toLowerCase().includes(commandSearch.toLowerCase()) ||
            cmd.desc.toLowerCase().includes(commandSearch.toLowerCase()),
        ),
      })).filter((cat) => !commandSearch || cat.commands.length > 0),
    [commandSearch],
  );

  const canonicalMethods = useMemo(
    () => new Set(commandCapabilities.canonical_methods ?? []),
    [commandCapabilities.canonical_methods],
  );
  const runtimeSupportedMethods = useMemo(
    () => new Set(commandCapabilities.runtime_supported_methods ?? []),
    [commandCapabilities.runtime_supported_methods],
  );

  const getCommandBlockReason = useCallback((method: string): CommandBlockReason | null => {
    const resolvedMethod = resolveCommandMethod(method);
    if (!canonicalMethods.has(resolvedMethod)) {
      return 'unknown_command';
    }
    if (!runtimeSupportedMethods.has(resolvedMethod)) {
      return 'not_supported_runtime';
    }
    return null;
  }, [canonicalMethods, runtimeSupportedMethods]);

  const riskBadge = (risk: string) => {
    const map: Record<string, string> = {
      low: 'text-green-400 bg-green-500/10 border-green-500/20',
      medium: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
      high: 'text-red-400 bg-red-500/10 border-red-500/20',
      critical: 'text-red-500 bg-red-500/20 border-red-500/40',
    };
    return map[risk] ?? 'text-muted-foreground bg-muted border-border';
  };

  const readApiError = async (response: Response): Promise<string> => {
    const payload = (await response.json().catch(() => null)) as Record<string, unknown> | null;
    const nestedError = payload?.error as Record<string, unknown> | undefined;
    const message = String(
      payload?.message ??
      payload?.reason ??
      nestedError?.message ??
      `Request failed (${response.status})`,
    );
    return message;
  };

  const pollCommandUntilTerminal = useCallback(async (commandId: string, method: string): Promise<void> => {
    const startedAt = Date.now();
    const timeoutMs = 90_000;

    while (Date.now() - startedAt < timeoutMs) {
      const response = await fetch(`/api/commands/${encodeURIComponent(commandId)}`, {
        credentials: 'include',
        cache: 'no-store',
      });

      if (!response.ok) {
        const errorMessage = await readApiError(response);
        throw new Error(errorMessage);
      }

      const payload = (await response.json()) as CommandDetailApiResponse;
      const state = (payload.state as CommandState) ?? 'queued';
      const outputPayload = {
        command_id: payload.command_id ?? commandId,
        device_id: device.id,
        method: payload.method ?? method,
        params: payload.params ?? {},
        state,
        result: payload.result ?? null,
        error_code: payload.error_code ?? null,
        error_message: payload.error_message ?? null,
        reason: payload.reason ?? null,
        completed_at: payload.completed_at ?? null,
      };

      setLiveResults((previous) => previous ? {
        ...previous,
        state,
        traceSteps: buildTraceSteps(method, state),
        output: isTerminalState(state) ? JSON.stringify(outputPayload, null, 2) : previous.output,
      } : {
        commandId,
        method,
        state,
        traceSteps: buildTraceSteps(method, state),
        output: isTerminalState(state) ? JSON.stringify(outputPayload, null, 2) : '',
      });

      if (isTerminalState(state)) {
        return;
      }

      await new Promise((resolve) => setTimeout(resolve, 2000));
    }

    throw new Error('Command polling timed out after 90 seconds.');
  }, [device.id]);

  const dispatchCommand = useCallback(async (
    method: string,
    params: Record<string, unknown>,
    label: string,
    sensitive = false,
  ) => {
    const dispatchMethod = resolveCommandMethod(method);
    const effectiveParams: Record<string, unknown> =
      dispatchMethod === 'list_files' && Object.keys(params).length === 0
        ? {
            path: 'C:\\Users',
            recursive: false,
            max_depth: 1,
            limit: 200,
            include_hidden: false,
            include_system: false,
            follow_symlinks: false,
          }
        : params;
    const blockReason = getCommandBlockReason(method);
    if (blockReason) {
      toast.error(`${label} blocked: ${reasonToText(blockReason)}`);
      return;
    }

    setIsDispatching(true);

    try {
      const response = await fetch('/api/commands', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          client_message_id: crypto.randomUUID(),
          device_id: device.id,
          method: dispatchMethod,
          params: effectiveParams,
          sensitive,
        }),
      });

      if (!response.ok) {
        const errorMessage = await readApiError(response);
        throw new Error(errorMessage);
      }

      const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
      const commandId = String(payload.command_id ?? '');
      if (!commandId) {
        throw new Error('Command dispatch failed: missing command_id');
      }

      setLiveResults({
        commandId,
        method: dispatchMethod,
        state: 'queued',
        output: '',
        traceSteps: buildTraceSteps(dispatchMethod, 'queued'),
      });
      setActiveTab('Trace');
      toast.success(`${label} dispatched (${commandId})`);

      await pollCommandUntilTerminal(commandId, dispatchMethod);
      await loadDeviceData();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Command dispatch failed';
      toast.error(message);
    } finally {
      setIsDispatching(false);
    }
  }, [device.id, getCommandBlockReason, loadDeviceData, pollCommandUntilTerminal]);

  const stateIcon = (s: CommandState) => {
    if (s === 'completed') return <CheckCircle size={12} className="text-green-400 flex-shrink-0" />;
    if (['failed', 'expired', 'rejected'].includes(s)) return <XCircle size={12} className="text-red-400 flex-shrink-0" />;
    if (['executing', 'ack_received'].includes(s)) return <Loader2 size={12} className="text-blue-400 flex-shrink-0 animate-spin" />;
    return <Clock size={12} className="text-amber-400 flex-shrink-0" />;
  };

  const featuredResult = useMemo(
    () => recentResults.find((row) => hasRenderableResult(row)) ?? recentResults[0] ?? null,
    [recentResults],
  );

  const activeCommandBlockReason = activeCommand ? getCommandBlockReason(activeCommand.id) : null;
  const scanAppsNow = useCallback(async () => {
    await dispatchCommand('list_processes', {}, 'Process List');
    setActiveTab('Overview');
  }, [dispatchCommand]);

  return (
    <div className="space-y-4 fade-in">
      {/* Back + Header */}
      <div className="flex items-start gap-4">
        <Link href="/device-management" className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors mt-1">
          <ArrowLeft size={13} /> Devices
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3 flex-wrap">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
              <Monitor size={18} className="text-muted-foreground" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-semibold tracking-tight">{device.hostname}</h1>
                <StatusBadge variant={device.status} pulse={device.status === 'online'} />
              </div>
              <p className="text-sm text-muted-foreground font-mono">{device.id} - {device.ipAddress} - {device.department} - {device.location}</p>
            </div>
            <div className="ml-auto flex items-center gap-2">
              <button
                onClick={() => {
                  void loadDeviceData();
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
              >
                <RefreshCw size={12} className={isLoadingDevice ? 'animate-spin' : ''} /> {isLoadingDevice ? 'Refreshing...' : 'Refresh'}
              </button>
              <Link href="/command-results" className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors">
                <BarChart2 size={12} /> View Results
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Quick stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
        {[
          { label: 'Risk Score', value: `${(device.riskScore * 100).toFixed(0)}/100`, color: riskColor },
          { label: 'Compliance', value: device.compliance.replace('_', ' '), color: device.compliance === 'compliant' ? 'text-green-400' : 'text-amber-400' },
          { label: 'CPU', value: device.cpu.split(' ').slice(0, 3).join(' '), color: 'text-foreground' },
          { label: 'RAM', value: device.ram, color: 'text-foreground' },
          { label: 'Uptime', value: device.uptime, color: 'text-foreground' },
          { label: 'Agent', value: `v${device.agentVersion}`, color: 'text-green-400' },
        ].map(s => (
          <div key={s.label} className="bg-card border border-border rounded-lg px-3 py-2.5">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-0.5">{s.label}</p>
            <p className={`text-xs font-semibold truncate ${s.color}`}>{s.value}</p>
          </div>
        ))}
      </div>

      {/* Main tabs */}
      <div className="flex items-center gap-0.5 border-b border-border overflow-x-auto scrollbar-thin">
        {mainTabs.map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2.5 text-xs font-medium border-b-2 transition-colors whitespace-nowrap ${
              activeTab === tab ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Overview ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Overview' && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="space-y-3">
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Device Identity</p>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'Hostname', value: device.hostname },
                  { label: 'Device ID', value: device.id },
                  { label: 'IP Address', value: device.ipAddress },
                  { label: 'OS Build', value: device.osBuild },
                  { label: 'Agent Version', value: device.agentVersion },
                  { label: 'Session ID', value: device.sessionId ?? '-' },
                  { label: 'Owner', value: device.owner },
                  { label: 'Department', value: device.department },
                  { label: 'Location', value: device.location },
                  { label: 'Last Seen', value: device.lastSeen },
                ].map(item => (
                  <div key={item.label} className="bg-muted/30 rounded-lg p-2.5">
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-0.5">{item.label}</p>
                    <p className="text-xs font-medium font-mono truncate">{item.value}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
          <div className="space-y-3">
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Security Posture</p>
              <div className="space-y-3">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <p className="text-xs text-muted-foreground">Risk Score</p>
                    <span className={`text-lg font-bold tabular-nums ${riskColor}`}>{(device.riskScore * 100).toFixed(0)}<span className="text-xs font-normal text-muted-foreground">/100</span></span>
                  </div>
                  <div className="h-2 bg-muted rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${device.riskScore > 0.6 ? 'bg-red-500' : device.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`} style={{ width: `${device.riskScore * 100}%` }} />
                  </div>
                </div>
                {[
                  {
                    label: 'Compliance',
                    value: device.compliance.replace('_', ' '),
                    state: device.compliance === 'compliant' ? 'ok' : 'warn',
                  },
                  {
                    label: 'Policy Sync',
                    value: device.policySync == null ? 'Unknown' : device.policySync ? 'Synchronized' : 'Hash mismatch',
                    state: device.policySync == null ? 'info' : device.policySync ? 'ok' : 'warn',
                  },
                  {
                    label: 'Kernel Guard',
                    value: device.kernelGuard == null ? 'Unknown' : device.kernelGuard ? 'KMDF driver active' : 'Driver not detected',
                    state: device.kernelGuard == null ? 'info' : device.kernelGuard ? 'ok' : 'warn',
                  },
                ].map(item => (
                  <div key={item.label} className="flex items-center justify-between py-2 border-b border-border/50 last:border-0">
                    <p className="text-xs text-muted-foreground">{item.label}</p>
                    <span
                      className={`text-xs font-medium ${
                        item.state === 'ok' ? 'text-green-400' : item.state === 'warn' ? 'text-amber-400' : 'text-blue-400'
                      }`}
                    >
                      {item.state === 'ok' ? 'OK' : item.state === 'warn' ? 'WARN' : 'INFO'} {item.value}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Quick Actions</p>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'System Info', icon: Info, tab: 'Commands', color: 'text-blue-400 bg-blue-500/10 border-blue-500/20' },
                  { label: 'Screenshot', icon: Camera, tab: 'Commands', color: 'text-purple-400 bg-purple-500/10 border-purple-500/20' },
                  { label: 'Process List', icon: List, tab: 'Commands', color: 'text-green-400 bg-green-500/10 border-green-500/20' },
                  { label: 'View History', icon: Clock, tab: 'History', color: 'text-amber-400 bg-amber-500/10 border-amber-500/20' },
                ].map(action => (
                  <button
                    key={action.label}
                    onClick={() => setActiveTab(action.tab)}
                    className={`flex items-center gap-2 px-3 py-2.5 text-xs font-medium border rounded-lg transition-colors hover:opacity-80 ${action.color}`}
                  >
                    <action.icon size={13} /> {action.label}
                  </button>
                ))}
              </div>
            </div>
            <DeviceAppLockQuickPanel
              deviceId={device.id}
              hostname={device.hostname}
              recentResults={recentResults}
              onScanApps={scanAppsNow}
              isScanningApps={isDispatching}
            />
          </div>
        </div>
      )}

      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Commands ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Commands' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          {/* Command library */}
          <div className="xl:col-span-2 space-y-3">
            <div className="relative">
              <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                placeholder="Search commands..."
                value={commandSearch}
                onChange={e => setCommandSearch(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
            </div>
            <div className="space-y-2 max-h-[60vh] overflow-y-auto scrollbar-thin pr-1">
              {filteredCategories.map(cat => (
                <div key={cat.category} className="bg-card border border-border rounded-lg overflow-hidden">
                  <button
                    className="w-full flex items-center gap-2 px-4 py-3 hover:bg-muted/30 transition-colors"
                    onClick={() => setSelectedCategory(selectedCategory === cat.category ? null : cat.category)}
                  >
                    <cat.icon size={14} className={cat.color} />
                    <span className="text-sm font-semibold flex-1 text-left">{cat.category}</span>
                    <span className="text-[11px] text-muted-foreground">{cat.commands.length} commands</span>
                    {selectedCategory === cat.category ? <ChevronUp size={13} className="text-muted-foreground" /> : <ChevronDown size={13} className="text-muted-foreground" />}
                  </button>
                  {(selectedCategory === cat.category || commandSearch) && (
                    <div className="border-t border-border divide-y divide-border/50">
                      {cat.commands.map((cmd) => {
                        const blockReason = getCommandBlockReason(cmd.id);
                        const isBlocked = Boolean(blockReason);
                        return (
                          <div
                            key={cmd.id}
                            onClick={() => setActiveCommand({ id: cmd.id, label: cmd.label, risk: cmd.risk })}
                            className={`flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors ${
                              isBlocked ? 'opacity-60 bg-muted/10' : 'hover:bg-muted/20'
                            } ${activeCommand?.id === cmd.id ? 'bg-primary/5 border-l-2 border-primary' : ''}`}
                          >
                            <cmd.icon size={14} className="text-muted-foreground flex-shrink-0" />
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium">{cmd.label}</p>
                              <p className="text-[11px] text-muted-foreground">{cmd.desc}</p>
                              {blockReason && (
                                <p className="text-[10px] text-amber-400 mt-1">Blocked: {reasonToText(blockReason)}</p>
                              )}
                            </div>
                            <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full border ${riskBadge(cmd.risk)}`}>{cmd.risk}</span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Dispatch panel */}
          <div className="xl:col-span-1">
            <div className="bg-card border border-border rounded-lg sticky top-4">
              <div className="px-4 py-3 border-b border-border">
                <p className="text-sm font-semibold">Dispatch Command</p>
                <p className="text-[11px] text-muted-foreground">Target: {device.hostname} ({device.id})</p>
              </div>
              <div className="p-4 space-y-3">
                {activeCommand ? (
                  <>
                    <div className="bg-muted/30 rounded-lg p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="text-sm font-semibold">{activeCommand.label}</p>
                        <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full border ${riskBadge(activeCommand.risk)}`}>{activeCommand.risk}</span>
                      </div>
                      <p className="text-[11px] font-mono text-muted-foreground">{activeCommand.id}</p>
                    </div>
                    <div>
                      <label className="text-[11px] text-muted-foreground mb-1 block">Parameters (JSON, optional)</label>
                      <textarea
                        value={commandParams}
                        onChange={e => setCommandParams(e.target.value)}
                        placeholder='{}'
                        rows={3}
                        className="w-full px-3 py-2 text-xs font-mono bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 resize-none"
                      />
                      {activeCommand.id === 'list_files' && (
                        <p className="mt-1 text-[11px] text-muted-foreground">
                          Default discovery is <span className="font-mono">C:\Users</span> when no path is set. Use <span className="font-mono">{`{"path":"C:\\\\"}`}</span> for full-drive scan.
                        </p>
                      )}
                    </div>
                    {['high', 'critical'].includes(activeCommand.risk) && (
                      <div className="flex items-start gap-2 bg-red-500/10 border border-red-500/20 rounded-lg p-3">
                        <AlertTriangle size={13} className="text-red-400 flex-shrink-0 mt-0.5" />
                        <p className="text-[11px] text-red-400">This is a {activeCommand.risk}-risk command. It will take immediate effect on {device.hostname}.</p>
                      </div>
                    )}
                    <button
                      onClick={async () => {
                        if (!activeCommand) return;
                        if (activeCommandBlockReason) {
                          toast.error(`${activeCommand.label} blocked: ${reasonToText(activeCommandBlockReason)}`);
                          return;
                        }
                        const parsed = parseJsonParams(commandParams);
                        if (!parsed.ok) {
                          toast.error(parsed.error);
                          return;
                        }
                        const sensitive = ['high', 'critical'].includes(activeCommand.risk);
                        await dispatchCommand(activeCommand.id, parsed.value, activeCommand.label, sensitive);
                      }}
                      disabled={isDispatching || device.status !== 'online' || Boolean(activeCommandBlockReason)}
                      className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                    >
                      {isDispatching ? <><Loader2 size={14} className="animate-spin" /> Dispatching...</> : <><Send size={14} /> Execute {activeCommand.label}</>}
                    </button>
                    {device.status !== 'online' && (
                      <p className="text-[11px] text-amber-400 text-center">Device is {device.status} - commands unavailable</p>
                    )}
                    {activeCommandBlockReason && (
                      <p className="text-[11px] text-amber-400 text-center">Blocked: {reasonToText(activeCommandBlockReason)}</p>
                    )}
                  </>
                ) : (
                  <div className="py-8 text-center">
                    <Terminal size={28} className="mx-auto text-muted-foreground/30 mb-2" />
                    <p className="text-sm text-muted-foreground">Select a command from the library</p>
                    <p className="text-[11px] text-muted-foreground/60 mt-1">Browse categories or search above</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Trace ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Trace' && (
        <div className="space-y-4">
          {liveResults ? (
            <div className="bg-card border border-border rounded-lg p-5">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="text-sm font-semibold">{liveResults.commandId} - {liveResults.method}</p>
                  <p className="text-[11px] text-muted-foreground">Live trace path: Web to Laravel to FastAPI to Agent to Back</p>
                </div>
                <StatusBadge variant={liveResults.state} />
              </div>
              <div className="relative">
                {liveResults.traceSteps.map((step, i) => (
                  <div key={step.label} className="flex items-start gap-4 mb-4 last:mb-0">
                    <div className="flex flex-col items-center">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
                        step.status === 'done' ? 'bg-green-500/20 border border-green-500/40' :
                        step.status === 'active' ? 'bg-blue-500/20 border border-blue-500/40 animate-pulse' :
                        step.status === 'error'? 'bg-red-500/20 border border-red-500/40' : 'bg-muted/40 border border-border'
                      }`}>
                        {step.status === 'done' ? <CheckCircle size={14} className="text-green-400" /> :
                         step.status === 'active' ? <Loader2 size={14} className="text-blue-400 animate-spin" /> :
                         step.status === 'error' ? <XCircle size={14} className="text-red-400" /> :
                         <Clock size={14} className="text-muted-foreground" />}
                      </div>
                      {i < liveResults.traceSteps.length - 1 && (
                        <div className={`w-0.5 h-8 mt-1 ${step.status === 'done' ? 'bg-green-500/40' : 'bg-border'}`} />
                      )}
                    </div>
                    <div className="flex-1 pt-1">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold">{step.label}</p>
                        {step.time && <span className="text-[11px] text-muted-foreground tabular-nums">{step.time}</span>}
                      </div>
                      <p className="text-[11px] text-muted-foreground">{step.detail}</p>
                    </div>
                  </div>
                ))}
              </div>
              {liveResults.output && (
                <div className="mt-4 border-t border-border pt-4">
                  <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Live Result Output</p>
                  <pre className="text-xs font-mono bg-muted/40 rounded-lg p-3 overflow-x-auto text-green-400">{liveResults.output}</pre>
                </div>
              )}
            </div>
          ) : (
            <div className="bg-card border border-border rounded-lg p-8 text-center">
              <Radio size={32} className="mx-auto text-muted-foreground/30 mb-3" />
              <p className="text-sm font-medium text-muted-foreground">No active trace</p>
              <p className="text-xs text-muted-foreground/60 mt-1">Dispatch a command from the Commands tab to see the live trace path</p>
              <button onClick={() => setActiveTab('Commands')} className="mt-4 flex items-center gap-1.5 px-4 py-2 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors mx-auto">
                <Terminal size={12} /> Go to Commands
              </button>
            </div>
          )}

          {/* Static trace diagram */}
          <div className="bg-card border border-border rounded-lg p-5">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-4">Architecture: Command Flow</p>
            <div className="flex items-center gap-2 flex-wrap">
              {[
                { label: 'Web UI', color: 'bg-blue-500/20 border-blue-500/40 text-blue-400' },
                { label: '->', color: '' },
                { label: 'Laravel API', color: 'bg-violet-500/20 border-violet-500/40 text-violet-400' },
                { label: '->', color: '' },
                { label: 'FastAPI Gateway', color: 'bg-amber-500/20 border-amber-500/40 text-amber-400' },
                { label: '->', color: '' },
                { label: 'Windows Agent', color: 'bg-green-500/20 border-green-500/40 text-green-400' },
                { label: '->', color: '' },
                { label: 'Result Return', color: 'bg-cyan-500/20 border-cyan-500/40 text-cyan-400' },
              ].map((node, i) => (
                node.label === '->' ? (
                  <ChevronRight key={i} size={16} className="text-muted-foreground" />
                ) : (
                  <div key={i} className={`px-3 py-1.5 rounded-lg border text-xs font-semibold ${node.color}`}>{node.label}</div>
                )
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Results ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Results' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Live command results for {device.hostname}</p>
            <Link href="/command-results" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              View all results <ChevronRight size={12} />
            </Link>
          </div>
          {liveResults?.output && liveResults.state !== 'completed' ? (
            <div className="bg-card border border-border rounded-lg p-4">
              <div className="flex items-center justify-between mb-3">
                <p className="text-sm font-semibold">{liveResults.commandId} - {liveResults.method}</p>
                <StatusBadge variant={liveResults.state} />
              </div>
              <pre className="text-xs font-mono bg-muted/40 rounded-lg p-3 overflow-x-auto text-green-400">{liveResults.output}</pre>
            </div>
          ) : null}

          {featuredResult ? (
            <div className="bg-card border border-border rounded-lg p-4">
              <CommandResultPresentation key={`device-result-${featuredResult.commandId}`} row={featuredResult} compact />
            </div>
          ) : (
            <div className="bg-card border border-border rounded-lg p-8 text-center">
              <BarChart2 size={32} className="mx-auto text-muted-foreground/30 mb-3" />
              <p className="text-sm font-medium text-muted-foreground">No results yet</p>
              <p className="text-xs text-muted-foreground/60 mt-1">Dispatch a command to see results here in real-time</p>
            </div>
          )}
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-border bg-muted/20 flex items-center justify-between">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Recent Result History</p>
              <span className="text-[11px] text-muted-foreground">{recentResults.length}</span>
            </div>
            {recentResults.length === 0 ? (
              <div className="px-4 py-6 text-sm text-muted-foreground text-center">No data available</div>
            ) : (
              <div className="divide-y divide-border">
                {recentResults.slice(0, 10).map((item) => (
                  <div key={`result-${item.commandId}`} className="px-4 py-3">
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-xs font-semibold font-mono truncate">{item.commandId}</p>
                        <p className="text-xs text-muted-foreground truncate">{item.method} · {item.actorEmail}</p>
                      </div>
                      <StatusBadge variant={item.state} size="sm" />
                    </div>
                    <div className="mt-2 flex items-center justify-between gap-2 text-[11px] text-muted-foreground">
                      <span>{formatTime(item.queuedAt)}{item.completedAt ? ` -> ${formatTime(item.completedAt)}` : ''}</span>
                      <span className="truncate text-right">
                        {item.resultNotes || item.errorMessage || item.reason || item.resultStatus || 'No data available'}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ History ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'History' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">{commandHistory.length} commands for {device.hostname}</p>
            <Link href="/command-history" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full history <ChevronRight size={12} />
            </Link>
          </div>
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            {commandHistory.length === 0 ? (
              <div className="p-6 text-center text-sm text-muted-foreground">No command history for this device yet.</div>
            ) : (
              <div className="divide-y divide-border">
                {commandHistory.map((cmd) => {
                  const replayBlockReason = getCommandBlockReason(cmd.method);
                  return (
                  <React.Fragment key={cmd.id}>
                    <div
                      className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                      onClick={() => setExpandedHistoryId(expandedHistoryId === cmd.id ? null : cmd.id)}
                    >
                      {stateIcon(cmd.state)}
                      <span className="font-mono text-[11px] text-primary font-semibold w-20">{cmd.id}</span>
                      <span className="text-xs font-medium flex-1">{cmd.method}</span>
                      <StatusBadge variant={cmd.state} size="sm" />
                      <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.queuedAt}</span>
                      <span className="text-[11px] text-muted-foreground">{cmd.duration ?? '-'}</span>
                      <button
                        onClick={async (e) => {
                          e.stopPropagation();
                          if (replayBlockReason) {
                            toast.error(`Replay blocked: ${reasonToText(replayBlockReason)}`);
                            return;
                          }
                          await dispatchCommand(cmd.method, cmd.params ?? {}, `Replay ${cmd.method}`);
                        }}
                        disabled={Boolean(replayBlockReason)}
                        className="flex items-center gap-1 px-2 py-0.5 text-[11px] bg-primary/10 border border-primary/20 text-primary rounded hover:bg-primary/20 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <RotateCcw size={9} /> Replay
                      </button>
                    </div>
                    {expandedHistoryId === cmd.id && (
                      <div className="px-4 py-3 bg-muted/10 border-t border-border/50">
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                          <div className="bg-muted/30 rounded p-2">
                            <p className="text-[10px] text-muted-foreground mb-0.5">Actor</p>
                            <p className="text-xs">{cmd.actor}</p>
                          </div>
                          <div className="bg-muted/30 rounded p-2">
                            <p className="text-[10px] text-muted-foreground mb-0.5">Completed</p>
                            <p className="text-xs">{cmd.completedAt ?? '-'}</p>
                          </div>
                          {cmd.resultPreview && (
                            <div className="bg-muted/30 rounded p-2 col-span-2">
                              <p className="text-[10px] text-muted-foreground mb-0.5">Result</p>
                              <p className="text-xs">{cmd.resultPreview}</p>
                            </div>
                          )}
                          {replayBlockReason && (
                            <div className="bg-muted/30 rounded p-2 col-span-2">
                              <p className="text-[10px] text-muted-foreground mb-0.5">Replay</p>
                              <p className="text-xs text-amber-400">Blocked: {reasonToText(replayBlockReason)}</p>
                            </div>
                          )}
                        </div>
                      </div>
                    )}
                  </React.Fragment>
                )})}
              </div>
            )}
          </div>
        </div>
      )}
      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Telemetry ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Telemetry' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Live telemetry for {device.hostname}</p>
            <Link href={`/telemetry-monitoring?device=${device.id}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full telemetry <ChevronRight size={12} />
            </Link>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {telemetryCards.map((metric) => {
              const numericValue = typeof metric.value === 'number' && Number.isFinite(metric.value)
                ? Math.max(0, Math.min(100, metric.value))
                : null;
              const displayValue = numericValue == null ? 'Unknown' : `${numericValue}%`;

              return (
                <div key={metric.label} className="bg-card border border-border rounded-lg p-4">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <metric.icon size={13} className="text-muted-foreground" />
                      <p className="text-sm font-medium">{metric.label}</p>
                    </div>
                    <span className="text-sm font-bold tabular-nums">{displayValue}</span>
                  </div>
                  <div className="h-2 bg-muted rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${metric.color} transition-all`} style={{ width: `${numericValue ?? 0}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
          <p className="text-[11px] text-muted-foreground text-center">
            Last snapshot: {telemetry.timestamp ? formatDateTime(telemetry.timestamp) : 'Unknown'}
          </p>
          <div className="text-[11px] text-muted-foreground grid grid-cols-1 md:grid-cols-2 gap-x-4 gap-y-1">
            {telemetryMetaRows.map((item) => (
              <p key={`telemetry-meta-${item.label}`} className="truncate">
                <span className="text-foreground/80">{item.label}:</span> {item.value}
              </p>
            ))}
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-2">
            {[
              {
                label: 'Kernel Events',
                value: kernelTelemetrySummary.total > 0 ? String(kernelTelemetrySummary.total) : 'No data available',
                color: 'text-foreground',
              },
              {
                label: 'Kernel Error Rate',
                value: kernelTelemetrySummary.errorRate == null ? 'No data available' : `${kernelTelemetrySummary.errorRate.toFixed(1)}%`,
                color: kernelTelemetrySummary.errorRate != null && kernelTelemetrySummary.errorRate >= 25 ? 'text-red-400' : 'text-green-400',
              },
              {
                label: 'Kernel Avg Latency',
                value: kernelTelemetrySummary.avgLatency == null ? 'No data available' : `${kernelTelemetrySummary.avgLatency.toFixed(1)}ms`,
                color: kernelTelemetrySummary.avgLatency != null && kernelTelemetrySummary.avgLatency >= 250 ? 'text-amber-400' : 'text-blue-400',
              },
              {
                label: 'Kernel Queue Depth',
                value: kernelTelemetrySummary.queueDepth == null ? 'No data available' : `${kernelTelemetrySummary.queueDepth.toFixed(0)}`,
                color: kernelTelemetrySummary.queueDepth != null && kernelTelemetrySummary.queueDepth > 0 ? 'text-amber-400' : 'text-green-400',
              },
            ].map((item) => (
              <div key={`device-kernel-summary-${item.label}`} className="bg-card border border-border rounded-lg px-3 py-2.5">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-0.5">{item.label}</p>
                <p className={`text-xs font-semibold tabular-nums ${item.color}`}>{item.value}</p>
              </div>
            ))}
          </div>
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-border flex items-center justify-between">
              <p className="text-xs font-medium">Recent Kernel Events</p>
              <p className="text-[10px] text-muted-foreground">telemetry_scope: kernel_event</p>
            </div>
            {kernelEvents.length === 0 ? (
              <div className="px-3 py-3 text-xs text-muted-foreground">
                {isLoadingDevice ? 'Loading telemetry data...' : 'No data available'}
              </div>
            ) : (
              <div className="divide-y divide-border">
                {kernelEvents.slice(0, 6).map((event) => (
                  <div key={event.id} className="px-3 py-2.5 flex items-center gap-3 text-xs">
                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-foreground/90 uppercase">{event.category}</span>
                    <span className="font-mono text-primary">{event.opcode}</span>
                    <span className={event.status === 'ok' ? 'text-green-400' : 'text-red-400'}>{event.status}</span>
                    <span className="text-muted-foreground tabular-nums ml-auto">{formatLocalTime(event.timestamp) ?? '--:--:--'}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Alerts ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {canViewAlerts && activeTab === 'Alerts' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Alerts for {device.hostname}</p>
            <Link href={`/alerts?device=${device.id}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              All alerts <ChevronRight size={12} />
            </Link>
          </div>
          <div className="space-y-2">
            {alerts.length === 0 ? (
              <div className="bg-card border border-border rounded-lg p-6 text-center text-sm text-muted-foreground">
                No alerts for this device.
              </div>
            ) : (
              alerts.map((alert) => (
                <div
                  key={alert.id}
                  className={`flex items-start gap-3 bg-card border rounded-lg p-4 ${
                    alert.severity === 'critical' || alert.severity === 'high'
                      ? 'border-red-500/30'
                      : alert.severity === 'medium'
                        ? 'border-amber-500/30'
                        : 'border-border'
                  }`}
                >
                  <AlertTriangle
                    size={14}
                    className={
                      alert.severity === 'critical' || alert.severity === 'high'
                        ? 'text-red-400'
                        : alert.severity === 'medium'
                          ? 'text-amber-400'
                          : 'text-muted-foreground'
                    }
                  />
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span
                        className={`text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded-full ${
                          alert.severity === 'critical' || alert.severity === 'high'
                            ? 'bg-red-500/10 text-red-400'
                            : alert.severity === 'medium'
                              ? 'bg-amber-500/10 text-amber-400'
                              : 'bg-muted text-muted-foreground'
                        }`}
                      >
                        {alert.severity}
                      </span>
                      <span className="text-[11px] text-muted-foreground">{alert.id}</span>
                    </div>
                    <p className="text-sm mt-1">{alert.message}</p>
                    <p className="text-[11px] text-muted-foreground mt-0.5">{alert.time} - {alert.status}</p>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      )}
      {/* ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ Audit ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ */}
      {activeTab === 'Audit' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Audit trail for {device.hostname}</p>
            <Link href="/audit" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full audit log <ChevronRight size={12} />
            </Link>
          </div>
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            {auditEntries.length === 0 ? (
              <div className="p-6 text-center text-sm text-muted-foreground">No audit entries for this device.</div>
            ) : (
              <div className="divide-y divide-border">
                {auditEntries.map((entry) => (
                  <div key={entry.id} className="flex items-center gap-3 px-4 py-3">
                    <div className={`w-2 h-2 rounded-full flex-shrink-0 ${entry.outcome === 'success' ? 'bg-green-500' : 'bg-red-500'}`} />
                    <span className="text-[11px] font-mono text-muted-foreground w-20">{entry.id}</span>
                    <span
                      className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${
                        entry.type === 'command'
                          ? 'bg-blue-500/10 text-blue-400'
                          : entry.type === 'policy'
                            ? 'bg-violet-500/10 text-violet-400'
                            : 'bg-muted text-muted-foreground'
                      }`}
                    >
                      {entry.type}
                    </span>
                    <span className="text-xs flex-1">{entry.action}</span>
                    <span className="text-[11px] text-muted-foreground">{entry.actor.split('@')[0]}</span>
                    <span className="text-[11px] text-muted-foreground tabular-nums">{entry.time}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}





