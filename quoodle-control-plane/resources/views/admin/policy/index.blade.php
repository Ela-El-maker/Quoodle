@extends('admin.layout')

@section('title', 'Policy')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Policy Viewer</h2>
            <p class="text-muted mb-0">Read-only policy bundles and risk tiers by capability.</p>
        </div>
        <button class="btn btn-outline-info">Upload Policy</button>
    </div>

    <div class="panel">
        <div class="panel-header">
            <h5 class="mb-0">Policy Profiles</h5>
        </div>
        <div class="panel-body">
            @forelse($profiles as $profile)
                <div class="mb-4">
                    <div class="fw-semibold">{{ $profile->profile_id }}</div>
                    <div class="text-muted small">{{ $profile->description }}</div>
                    <pre class="bg-black bg-opacity-25 p-3 rounded text-xs text-slate-200 mt-2">{{ json_encode($profile->rules, JSON_PRETTY_PRINT) }}</pre>
                </div>
            @empty
                <div class="text-muted">No policy profiles found.</div>
            @endforelse
        </div>
    </div>
@endsection
