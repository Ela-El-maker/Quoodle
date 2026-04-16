using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using QRCoder;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class OnboardingPage : Page
{
    private readonly OnboardingViewModel _vm;
    private readonly TextBox[] _tokenBoxes;
    private bool _syncingTokenBoxes;
    private bool _renderQueued;
    private string _lastRenderedQrPayload = string.Empty;

    public OnboardingPage()
    {
        InitializeComponent();
        _vm = new OnboardingViewModel(App.StateStore);
        _vm.PropertyChanged += HandleViewModelPropertyChanged;
        Unloaded += OnPageUnloaded;

        _tokenBoxes = new[] { TokenBox0, TokenBox1, TokenBox2, TokenBox3, TokenBox4, TokenBox5 };

        Render();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        QueueRender();
    }

    private void QueueRender()
    {
        if (_renderQueued)
        {
            return;
        }

        _renderQueued = true;
        if (DispatcherQueue.HasThreadAccess)
        {
            _renderQueued = false;
            RenderCore();
            return;
        }

        _ = DispatcherQueue.TryEnqueue(() =>
        {
            _renderQueued = false;
            RenderCore();
        });
    }

    private void Render()
    {
        _renderQueued = false;
        RenderCore();
    }

    private void RenderCore()
    {
        RenderStepRail();
        RenderDetectStage();
        RenderPairStage();
        RenderConfirmStage();
    }

    private void RenderStepRail()
    {
        ApplyStepVisual(
            StepDetectChip,
            StepDetectChipText,
            StepDetectLabel,
            stepNumber: "1",
            isCurrent: _vm.IsStepDetectCurrent,
            isComplete: _vm.IsStepDetectComplete,
            allowCheckIcon: true);

        ApplyStepVisual(
            StepPairChip,
            StepPairChipText,
            StepPairLabel,
            stepNumber: "2",
            isCurrent: _vm.IsStepPairCurrent,
            isComplete: _vm.IsStepPairComplete,
            allowCheckIcon: true);

        ApplyStepVisual(
            StepConfirmChip,
            StepConfirmChipText,
            StepConfirmLabel,
            stepNumber: "3",
            isCurrent: _vm.IsStepConfirmCurrent,
            isComplete: _vm.IsStepConfirmComplete,
            allowCheckIcon: false);

        StepDetectLine.Background = _vm.IsStepDetectComplete ? BrushOf("SuccessBrush") : BrushOf("BorderBrush");
        StepPairLine.Background = _vm.IsStepPairComplete ? BrushOf("SuccessBrush") : BrushOf("BorderBrush");
    }

    private void RenderDetectStage()
    {
        DetectCard.Visibility = _vm.IsDetectStage ? Visibility.Visible : Visibility.Collapsed;

        CheckStatusButton.Visibility = _vm.IsDetectIdle ? Visibility.Visible : Visibility.Collapsed;
        CheckStatusButton.IsEnabled = _vm.CheckEnrollmentCommand.CanExecute(null);

        DetectCheckingPanel.Visibility = _vm.IsDetectChecking ? Visibility.Visible : Visibility.Collapsed;
        DetectWarningPanel.Visibility = _vm.IsDetectNotEnrolled ? Visibility.Visible : Visibility.Collapsed;

        BeginPairingButton.Visibility = _vm.IsDetectNotEnrolled ? Visibility.Visible : Visibility.Collapsed;
        BeginPairingButton.IsEnabled = _vm.BeginPairingCommand.CanExecute(null);
    }

    private void RenderPairStage()
    {
        PairCard.Visibility = _vm.IsPairStage ? Visibility.Visible : Visibility.Collapsed;
        if (!_vm.IsPairStage)
        {
            return;
        }

        TokenPane.Visibility = _vm.IsPairTokenMode ? Visibility.Visible : Visibility.Collapsed;
        QrPane.Visibility = _vm.IsPairQrMode ? Visibility.Visible : Visibility.Collapsed;

        ApplyPairTabVisual(TokenTabButton, _vm.IsPairTokenMode);
        ApplyPairTabVisual(QrTabButton, _vm.IsPairQrMode);

        VerifyTokenButton.IsEnabled = _vm.VerifyTokenCommand.CanExecute(null);
        TokenEntryPanel.IsHitTestVisible = !_vm.IsTokenVerifying;
        TokenEntryPanel.Opacity = _vm.IsTokenVerifying ? 0.55 : 1.0;
        TokenVerifyingPanel.Visibility = _vm.IsTokenVerifying ? Visibility.Visible : Visibility.Collapsed;

        TokenErrorPanel.Visibility = _vm.IsTokenFailed ? Visibility.Visible : Visibility.Collapsed;
        TokenErrorText.Text = _vm.PairError;
        RetryPairingButton.IsEnabled = _vm.RetryPairingCommand.CanExecute(null);

        SyncTokenBoxesFromViewModel();
        UpdateTokenBoxVisualState();

        if (_vm.IsPairQrMode)
        {
            if (!string.Equals(_lastRenderedQrPayload, _vm.PairingString, StringComparison.Ordinal))
            {
                _ = RenderQrPatternAsync(_vm.PairingString);
                _lastRenderedQrPayload = _vm.PairingString;
            }
        }
        else
        {
            _lastRenderedQrPayload = string.Empty;
            QrImage.Source = null;
        }
    }

    private void RenderConfirmStage()
    {
        ConfirmCard.Visibility = _vm.IsConfirmStage ? Visibility.Visible : Visibility.Collapsed;
        if (!_vm.IsConfirmStage)
        {
            return;
        }

        RegisteringPanel.Visibility = _vm.IsRegistering ? Visibility.Visible : Visibility.Collapsed;
        EnrollmentCompletePanel.Visibility = _vm.IsEnrollmentComplete ? Visibility.Visible : Visibility.Collapsed;

        PendingDeviceNameText.Text = _vm.EnrollmentDeviceName;
        PendingDeviceIdSuffixText.Text = _vm.EnrollmentDeviceIdSuffix;
        RegisteringStatusText.Text = _vm.StatusLine;

        EnrollmentDeviceNameText.Text = _vm.EnrollmentDeviceName;
        EnrollmentDeviceIdText.Text = _vm.EnrollmentDeviceId;
        EnrollmentPlatformText.Text = _vm.EnrollmentPlatform;
        EnrollmentAgentVersionText.Text = _vm.EnrollmentAgentVersion;
        EnrollmentAtText.Text = _vm.EnrollmentAt;
        EnrollmentPolicyHashText.Text = _vm.EnrollmentPolicyHash;

        OpenDashboardButton.IsEnabled = _vm.IsEnrollmentComplete;
        ConfigureAgentButton.IsEnabled = _vm.IsEnrollmentComplete;
    }

    private void ApplyStepVisual(
        Border chip,
        TextBlock chipText,
        TextBlock label,
        string stepNumber,
        bool isCurrent,
        bool isComplete,
        bool allowCheckIcon)
    {
        if (isCurrent || isComplete)
        {
            chip.Background = BrushOf("ChipSuccessBackgroundBrush");
            chip.BorderBrush = BrushOf("SuccessBrush");
            label.Foreground = BrushOf("TextPrimaryBrush");
            chipText.Foreground = BrushOf("SuccessBrush");

            if (allowCheckIcon && isComplete && !isCurrent)
            {
                chipText.Text = "✓";
            }
            else
            {
                chipText.Text = stepNumber;
            }

            return;
        }

        chip.Background = BrushOf("SurfaceAltBrush");
        chip.BorderBrush = BrushOf("BorderBrush");
        chipText.Foreground = BrushOf("TextMutedBrush");
        label.Foreground = BrushOf("TextMutedBrush");
        chipText.Text = stepNumber;
    }

    private void ApplyPairTabVisual(Button button, bool selected)
    {
        button.Background = selected ? BrushOf("SurfaceBrush") : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.Foreground = selected ? BrushOf("TextPrimaryBrush") : BrushOf("TextMutedBrush");
        button.BorderThickness = new Thickness(0);
        button.Opacity = selected ? 1 : 0.92;
    }

    private void SyncTokenBoxesFromViewModel()
    {
        _syncingTokenBoxes = true;
        for (var i = 0; i < _tokenBoxes.Length; i++)
        {
            _tokenBoxes[i].Text = _vm.TokenDigitAt(i);
        }

        _syncingTokenBoxes = false;
    }

    private void UpdateTokenBoxVisualState()
    {
        for (var i = 0; i < _tokenBoxes.Length; i++)
        {
            var hasDigit = !string.IsNullOrWhiteSpace(_tokenBoxes[i].Text);
            _tokenBoxes[i].BorderBrush = hasDigit ? BrushOf("SuccessBrush") : BrushOf("InputBorderBrush");
        }
    }

    private async Task RenderQrPatternAsync(string payload)
    {
        var safePayload = string.IsNullOrWhiteSpace(payload) ? "quoodle_pair_pending" : payload;
        using var generator = new QRCodeGenerator();
        using var qrData = generator.CreateQrCode(safePayload, QRCodeGenerator.ECCLevel.M);
        var qrPng = new PngByteQRCode(qrData);
        var pngBytes = qrPng.GetGraphic(8);

        using var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(pngBytes.AsBuffer());
        stream.Seek(0);

        var bitmap = new BitmapImage();
        await bitmap.SetSourceAsync(stream);
        QrImage.Source = bitmap;
    }

    private Brush BrushOf(string key)
    {
        return Application.Current.Resources[key] as Brush ?? new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private void OnCheckStatus(object sender, RoutedEventArgs e)
    {
        if (_vm.CheckEnrollmentCommand.CanExecute(null))
        {
            _vm.CheckEnrollmentCommand.Execute(null);
        }
    }

    private void OnBeginPairing(object sender, RoutedEventArgs e)
    {
        if (_vm.BeginPairingCommand.CanExecute(null))
        {
            _vm.BeginPairingCommand.Execute(null);
        }
    }

    private void OnSelectTokenMode(object sender, RoutedEventArgs e)
    {
        if (_vm.SelectTokenModeCommand.CanExecute(null))
        {
            _vm.SelectTokenModeCommand.Execute(null);
        }
    }

    private void OnSelectQrMode(object sender, RoutedEventArgs e)
    {
        if (_vm.SelectQrModeCommand.CanExecute(null))
        {
            _vm.SelectQrModeCommand.Execute(null);
        }
    }

    private void OnVerifyToken(object sender, RoutedEventArgs e)
    {
        if (_vm.VerifyTokenCommand.CanExecute(null))
        {
            _vm.VerifyTokenCommand.Execute(null);
        }
    }

    private void OnRetryPairing(object sender, RoutedEventArgs e)
    {
        if (_vm.RetryPairingCommand.CanExecute(null))
        {
            _vm.RetryPairingCommand.Execute(null);
        }
    }

    private void OnTokenDigitChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncingTokenBoxes || sender is not TextBox box)
        {
            return;
        }

        var index = Array.IndexOf(_tokenBoxes, box);
        if (index < 0)
        {
            return;
        }

        var typed = new string((box.Text ?? string.Empty).Where(char.IsDigit).ToArray());
        if (typed.Length > 1)
        {
            _vm.SetTokenDigits(typed);
            SyncTokenBoxesFromViewModel();
            var nextIndex = Math.Min(typed.Length, _tokenBoxes.Length - 1);
            _tokenBoxes[nextIndex].Focus(FocusState.Programmatic);
            _tokenBoxes[nextIndex].SelectAll();
            return;
        }

        var digit = typed.Length == 1 ? typed : string.Empty;
        _vm.SetTokenDigit(index, digit);

        if (!string.IsNullOrEmpty(digit) && index < _tokenBoxes.Length - 1)
        {
            _tokenBoxes[index + 1].Focus(FocusState.Programmatic);
            _tokenBoxes[index + 1].SelectAll();
        }

        UpdateTokenBoxVisualState();
    }

    private void OnTokenDigitKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (sender is not TextBox box)
        {
            return;
        }

        var index = Array.IndexOf(_tokenBoxes, box);
        if (index < 0)
        {
            return;
        }

        if (e.Key == Windows.System.VirtualKey.Back)
        {
            if (string.IsNullOrEmpty(box.Text) && index > 0)
            {
                _vm.BackspaceTokenDigit(index - 1);
                _tokenBoxes[index - 1].Focus(FocusState.Programmatic);
                _tokenBoxes[index - 1].SelectAll();
                e.Handled = true;
                UpdateTokenBoxVisualState();
                return;
            }

            _vm.BackspaceTokenDigit(index);
            UpdateTokenBoxVisualState();
            return;
        }

        if (e.Key == Windows.System.VirtualKey.Left && index > 0)
        {
            _tokenBoxes[index - 1].Focus(FocusState.Programmatic);
            _tokenBoxes[index - 1].SelectAll();
            e.Handled = true;
            return;
        }

        if (e.Key == Windows.System.VirtualKey.Right && index < _tokenBoxes.Length - 1)
        {
            _tokenBoxes[index + 1].Focus(FocusState.Programmatic);
            _tokenBoxes[index + 1].SelectAll();
            e.Handled = true;
        }
    }

    private void OnCopyPairingString(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(_vm.PairingString);
        Clipboard.SetContent(package);
    }

    private void OnOpenDashboard(object sender, RoutedEventArgs e)
    {
        Frame?.Navigate(typeof(DashboardPage));
    }

    private void OnConfigureAgent(object sender, RoutedEventArgs e)
    {
        Frame?.Navigate(typeof(SettingsPage));
    }

    private void OnPageUnloaded(object sender, RoutedEventArgs e)
    {
        Unloaded -= OnPageUnloaded;
        _vm.PropertyChanged -= HandleViewModelPropertyChanged;
        _vm.Dispose();
    }
}
