<?php

namespace App\Providers;

use App\Models\Alert;
use App\Models\Device;
use App\Observers\AlertObserver;
use App\Observers\DeviceObserver;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Device::observe(DeviceObserver::class);
        Alert::observe(AlertObserver::class);
    }
}
