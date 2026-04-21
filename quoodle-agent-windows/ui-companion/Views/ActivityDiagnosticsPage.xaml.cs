using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Dispatching;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class ActivityDiagnosticsPage : Page
{
    private readonly ActivityDiagnosticsViewModel _vm;
    private readonly Dictionary<ActivityDiagnosticsTab, Dictionary<string, TextBlock>> _sortGlyphMap;
    private readonly DispatcherQueueTimer _searchDebounceTimer;
    private bool _isRendering;
    private string _pendingSearchQuery = string.Empty;
    private string _appliedSearchQuery = string.Empty;
    private string _lastRenderedRawJson = string.Empty;
    private string _lastRenderedRawSize = string.Empty;

    public ActivityDiagnosticsPage()
    {
        InitializeComponent();

        _vm = new ActivityDiagnosticsViewModel(App.StateStore);
        _vm.PropertyChanged += HandleViewModelPropertyChanged;

        _searchDebounceTimer = DispatcherQueue.CreateTimer();
        _searchDebounceTimer.Interval = TimeSpan.FromMilliseconds(180);
        _searchDebounceTimer.IsRepeating = false;
        _searchDebounceTimer.Tick += OnSearchDebounceTimerTick;

        _sortGlyphMap = new Dictionary<ActivityDiagnosticsTab, Dictionary<string, TextBlock>>
        {
            [ActivityDiagnosticsTab.WssMessageLog] = new Dictionary<string, TextBlock>(StringComparer.OrdinalIgnoreCase)
            {
                ["seq"] = WssSeqSortGlyph,
                ["type"] = WssTypeSortGlyph,
                ["from"] = WssFromSortGlyph,
                ["message_id"] = WssMessageIdSortGlyph,
                ["timestamp"] = WssTimestampSortGlyph,
                ["body_summary"] = WssBodySummarySortGlyph,
                ["sig"] = WssSigSortGlyph
            },
            [ActivityDiagnosticsTab.CommandHistory] = new Dictionary<string, TextBlock>(StringComparer.OrdinalIgnoreCase)
            {
                ["command_id"] = CmdCommandIdSortGlyph,
                ["method"] = CmdMethodSortGlyph,
                ["priority"] = CmdPrioritySortGlyph,
                ["state"] = CmdStateSortGlyph,
                ["exec_path"] = CmdExecPathSortGlyph,
                ["kernel_exec_id"] = CmdKernelExecIdSortGlyph,
                ["issued_at"] = CmdIssuedAtSortGlyph,
                ["duration"] = CmdDurationSortGlyph,
                ["origin_user"] = CmdOriginUserSortGlyph
            },
            [ActivityDiagnosticsTab.KernelEvents] = new Dictionary<string, TextBlock>(StringComparer.OrdinalIgnoreCase)
            {
                ["event_id"] = KerEventIdSortGlyph,
                ["event_type"] = KerEventTypeSortGlyph,
                ["opcode"] = KerOpcodeSortGlyph,
                ["status"] = KerStatusSortGlyph,
                ["error_code"] = KerErrorCodeSortGlyph,
                ["kernel_exec_id"] = KerKernelExecIdSortGlyph,
                ["agent_seq"] = KerAgentSeqSortGlyph,
                ["command_id"] = KerCommandIdSortGlyph,
                ["timestamp"] = KerTimestampSortGlyph
            }
        };

        Unloaded += OnPageUnloaded;
        SizeChanged += (_, _) => UpdateRawOverlayLayout();
        Render();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (DispatcherQueue.HasThreadAccess)
        {
            Render();
            return;
        }

        _ = DispatcherQueue.TryEnqueue(Render);
    }

    private void Render()
    {
        _isRendering = true;
        try
        {
            WssTabCountText.Text = _vm.WssCount.ToString();
            CommandTabCountText.Text = _vm.CommandCount.ToString();
            KernelTabCountText.Text = _vm.KernelCount.ToString();

            RenderTabState();
            RenderFilters();
            RenderTableFooter();
            RenderRawPanel();
            RenderSortGlyphs();
        }
        finally
        {
            _isRendering = false;
        }
    }

    private void RenderTabState()
    {
        BindActiveTableSource();
        SetTabVisual(WssTabSurface, WssTabLabelText, WssTabBadge, WssTabCountText, _vm.IsWssTab);
        SetTabVisual(CommandTabSurface, CommandTabLabelText, CommandTabBadge, CommandTabCountText, _vm.IsCommandTab);
        SetTabVisual(KernelTabSurface, KernelTabLabelText, KernelTabBadge, KernelTabCountText, _vm.IsKernelTab);

        WssHeaderRow.Visibility = _vm.IsWssTab ? Visibility.Visible : Visibility.Collapsed;
        WssListView.Visibility = _vm.IsWssTab ? Visibility.Visible : Visibility.Collapsed;
        CommandHeaderRow.Visibility = _vm.IsCommandTab ? Visibility.Visible : Visibility.Collapsed;
        CommandListView.Visibility = _vm.IsCommandTab ? Visibility.Visible : Visibility.Collapsed;
        KernelHeaderRow.Visibility = _vm.IsKernelTab ? Visibility.Visible : Visibility.Collapsed;
        KernelListView.Visibility = _vm.IsKernelTab ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RenderFilters()
    {
        SearchBox.PlaceholderText = _vm.SearchPlaceholder;
        if (!string.Equals(SearchBox.Text, _vm.SearchQuery, StringComparison.Ordinal))
        {
            SearchBox.Text = _vm.SearchQuery;
        }
        _appliedSearchQuery = _vm.SearchQuery;
        _pendingSearchQuery = _vm.SearchQuery;

        Filter1Box.ItemsSource = _vm.Filter1Options;
        Filter1Box.SelectedItem = _vm.SelectedFilter1;

        Filter2Box.ItemsSource = _vm.Filter2Options;
        Filter2Box.SelectedItem = _vm.SelectedFilter2;

        Filter3Box.ItemsSource = _vm.Filter3Options;
        Filter3Box.SelectedItem = _vm.SelectedFilter3;
        Filter3Box.Visibility = _vm.Filter3Visible ? Visibility.Visible : Visibility.Collapsed;
        ToolbarFilter3Column.Width = _vm.Filter3Visible ? new GridLength(1.2, GridUnitType.Star) : new GridLength(0);
        Grid.SetColumn(ExportJsonButton, 4);
    }

    private void RenderTableFooter()
    {
        TableFooterText.Text = _vm.TableFooter;
        CurrentPageText.Text = _vm.PagePill;
        PrevPageButton.IsEnabled = _vm.CanPrevPage;
        NextPageButton.IsEnabled = _vm.CanNextPage;
    }

    private void RenderRawPanel()
    {
        var showInspector = _vm.HasRawSelection;
        RawOverlayLayer.Visibility = showInspector ? Visibility.Visible : Visibility.Collapsed;
        CopyRawButton.IsEnabled = showInspector;

        if (!showInspector)
        {
            return;
        }

        UpdateRawOverlayLayout();

        if (!string.Equals(_lastRenderedRawJson, _vm.RawMessageJson, StringComparison.Ordinal))
        {
            RawJsonTextBlock.Text = _vm.RawMessageJson;
            _lastRenderedRawJson = _vm.RawMessageJson;
        }

        if (!string.Equals(_lastRenderedRawSize, _vm.RawSizeText, StringComparison.Ordinal))
        {
            RawSizeTextBlock.Text = _vm.RawSizeText;
            _lastRenderedRawSize = _vm.RawSizeText;
        }
    }

    private void UpdateRawOverlayLayout()
    {
        var width = ActualWidth;
        if (width < 640)
        {
            RawOverlayHost.HorizontalAlignment = HorizontalAlignment.Stretch;
            RawOverlayHost.Width = double.NaN;
            RawOverlayHost.MaxWidth = double.PositiveInfinity;
            RawOverlayHost.Margin = new Thickness(8);
            return;
        }

        RawOverlayHost.HorizontalAlignment = HorizontalAlignment.Right;
        RawOverlayHost.Margin = width < 1008 ? new Thickness(10) : new Thickness(12);
        RawOverlayHost.Width = width < 1008 ? 428 : 480;
        RawOverlayHost.MaxWidth = width < 1008 ? 448 : 520;
    }

    private void RenderSortGlyphs()
    {
        var muted = BrushOf("TextMutedBrush");
        foreach (var glyph in _sortGlyphMap.SelectMany(x => x.Value.Values))
        {
            glyph.Text = string.Empty;
            glyph.Foreground = muted;
        }

        if (!_sortGlyphMap.TryGetValue(_vm.ActiveTab, out var activeMap))
        {
            return;
        }

        foreach (var entry in activeMap)
        {
            if (!_vm.IsSortColumn(entry.Key))
            {
                continue;
            }

            entry.Value.Text = _vm.IsSortDescending() ? "v" : "^";
            entry.Value.Foreground = BrushOf("SuccessBrush");
        }
    }

    private void BindActiveTableSource()
    {
        WssListView.ItemsSource = _vm.IsWssTab ? _vm.WssRows : null;
        CommandListView.ItemsSource = _vm.IsCommandTab ? _vm.CommandRows : null;
        KernelListView.ItemsSource = _vm.IsKernelTab ? _vm.KernelRows : null;
    }

    private void OnSearchDebounceTimerTick(DispatcherQueueTimer sender, object args)
    {
        sender.Stop();
        if (string.Equals(_pendingSearchQuery, _appliedSearchQuery, StringComparison.Ordinal))
        {
            return;
        }

        _appliedSearchQuery = _pendingSearchQuery;
        _vm.SetSearch(_pendingSearchQuery);
    }

    private void SetTabVisual(Border surface, TextBlock label, Border badge, TextBlock badgeText, bool active)
    {
        surface.Background = active ? BrushOf("SurfaceAltBrush") : BrushOf("SurfaceBrush");
        surface.BorderBrush = active ? BrushOf("HeaderPanelBorderBrush") : BrushOf("BorderBrush");
        label.Foreground = active ? BrushOf("TextPrimaryBrush") : BrushOf("TextMutedBrush");
        badge.Background = active ? BrushOf("ChipNeutralBackgroundBrush") : BrushOf("SurfaceAltBrush");
        badgeText.Foreground = active ? BrushOf("TextSecondaryBrush") : BrushOf("TextMutedBrush");
    }

    private Brush BrushOf(string key)
    {
        if (Resources.TryGetValue(key, out var localObj) && localObj is Brush localBrush)
        {
            return localBrush;
        }

        if (Application.Current.Resources.TryGetValue(key, out var appObj) && appObj is Brush appBrush)
        {
            return appBrush;
        }

        return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private void OnWssTabClick(object sender, RoutedEventArgs e)
    {
        _vm.SelectTab(ActivityDiagnosticsTab.WssMessageLog);
    }

    private void OnCommandTabClick(object sender, RoutedEventArgs e)
    {
        _vm.SelectTab(ActivityDiagnosticsTab.CommandHistory);
    }

    private void OnKernelTabClick(object sender, RoutedEventArgs e)
    {
        _vm.SelectTab(ActivityDiagnosticsTab.KernelEvents);
    }

    private void OnSearchTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _pendingSearchQuery = SearchBox.Text ?? string.Empty;
        _searchDebounceTimer.Stop();
        _searchDebounceTimer.Start();
    }

    private void OnFilter1Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        if (Filter1Box.SelectedItem is string value)
        {
            _vm.SetFilter1(value);
        }
    }

    private void OnFilter2Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        if (Filter2Box.SelectedItem is string value)
        {
            _vm.SetFilter2(value);
        }
    }

    private void OnFilter3Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering || !_vm.Filter3Visible)
        {
            return;
        }

        if (Filter3Box.SelectedItem is string value)
        {
            _vm.SetFilter3(value);
        }
    }

    private void OnSortColumnClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is string column)
        {
            _vm.ToggleSort(column);
        }
    }

    private void OnWssRowSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.SelectWssRow(WssListView.SelectedItem as WssMessageLogRowView);
    }

    private void OnCommandRowSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.SelectCommandRow(CommandListView.SelectedItem as CommandHistoryRowView);
    }

    private void OnKernelRowSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.SelectKernelRow(KernelListView.SelectedItem as KernelEventRowView);
    }

    private void OnPrevPageClick(object sender, RoutedEventArgs e)
    {
        _vm.PrevPage();
    }

    private void OnNextPageClick(object sender, RoutedEventArgs e)
    {
        _vm.NextPage();
    }

    private void OnCopyRawClick(object sender, RoutedEventArgs e)
    {
        if (!_vm.HasRawSelection)
        {
            return;
        }

        var package = new DataPackage();
        package.SetText(_vm.RawMessageJson);
        Clipboard.SetContent(package);
    }

    private void OnCloseRawOverlayClick(object sender, RoutedEventArgs e)
    {
        ClearRawSelection();
    }

    private void OnPageKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Escape || !_vm.HasRawSelection)
        {
            return;
        }

        ClearRawSelection();
        e.Handled = true;
    }

    private void ClearRawSelection()
    {
        _vm.ClearRawMessage();
        WssListView.SelectedItem = null;
        CommandListView.SelectedItem = null;
        KernelListView.SelectedItem = null;
    }

    private async void OnExportJson(object sender, RoutedEventArgs e)
    {
        try
        {
            var json = _vm.BuildCurrentViewExportJson();

            var picker = new FileSavePicker
            {
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
                SuggestedFileName = $"{GetActiveTabFilePrefix()}-{DateTimeOffset.Now:yyyyMMdd-HHmmss}"
            };
            picker.FileTypeChoices.Add("JSON", new List<string> { ".json" });

            var windowHandle = App.MainWindowHandle;
            if (windowHandle != IntPtr.Zero)
            {
                InitializeWithWindow.Initialize(picker, windowHandle);
            }

            var file = await picker.PickSaveFileAsync();
            if (file is null)
            {
                return;
            }

            await FileIO.WriteTextAsync(file, json);
        }
        catch
        {
            // Best-effort export action.
        }
    }

    private string GetActiveTabFilePrefix()
    {
        return _vm.ActiveTab switch
        {
            ActivityDiagnosticsTab.WssMessageLog => "wss-message-log",
            ActivityDiagnosticsTab.CommandHistory => "command-history",
            ActivityDiagnosticsTab.KernelEvents => "kernel-events",
            _ => "activity-diagnostics"
        };
    }

    private void OnPageUnloaded(object sender, RoutedEventArgs e)
    {
        Unloaded -= OnPageUnloaded;
        _searchDebounceTimer.Stop();
        _searchDebounceTimer.Tick -= OnSearchDebounceTimerTick;
        _vm.PropertyChanged -= HandleViewModelPropertyChanged;
        _vm.Dispose();
    }
}

