using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;
using System.Security.Cryptography;
using System.Text;
using Windows.ApplicationModel.DataTransfer;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class OnboardingPage : Page
{
    private readonly OnboardingViewModel _vm;
    private readonly TextBox[] _tokenBoxes;
    private bool _syncingTokenBoxes;

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
        if (DispatcherQueue.HasThreadAccess)
        {
            Render();
            return;
        }

        _ = DispatcherQueue.TryEnqueue(Render);
    }

    private void Render()
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
            RenderQrPattern(_vm.PairingString);
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

    private void RenderQrPattern(string payload)
    {
        QrGrid.Children.Clear();
        QrGrid.RowDefinitions.Clear();
        QrGrid.ColumnDefinitions.Clear();

        const int size = 21;
        for (var i = 0; i < size; i++)
        {
            QrGrid.RowDefinitions.Add(new RowDefinition());
            QrGrid.ColumnDefinitions.Add(new ColumnDefinition());
        }

        var modules = BuildPseudoQrModules(payload, size);
        for (var row = 0; row < size; row++)
        {
            for (var col = 0; col < size; col++)
            {
                var rect = new Rectangle
                {
                    Fill = modules[row, col] ? new SolidColorBrush(Microsoft.UI.Colors.Black) : new SolidColorBrush(Microsoft.UI.Colors.White)
                };

                Grid.SetRow(rect, row);
                Grid.SetColumn(rect, col);
                QrGrid.Children.Add(rect);
            }
        }
    }

    private static bool[,] BuildPseudoQrModules(string payload, int size)
    {
        var modules = new bool[size, size];

        PlaceFinder(modules, 0, 0);
        PlaceFinder(modules, 0, size - 7);
        PlaceFinder(modules, size - 7, 0);

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(payload));
        var bit = 0;
        for (var row = 0; row < size; row++)
        {
            for (var col = 0; col < size; col++)
            {
                if (InFinderArea(row, col, size))
                {
                    continue;
                }

                var byteIdx = (bit / 8) % hash.Length;
                var bitMask = 1 << (bit % 8);
                modules[row, col] = (hash[byteIdx] & bitMask) != 0;
                bit++;
            }
        }

        return modules;
    }

    private static bool InFinderArea(int row, int col, int size)
    {
        bool topLeft = row < 7 && col < 7;
        bool topRight = row < 7 && col >= size - 7;
        bool bottomLeft = row >= size - 7 && col < 7;
        return topLeft || topRight || bottomLeft;
    }

    private static void PlaceFinder(bool[,] modules, int rowStart, int colStart)
    {
        for (var row = 0; row < 7; row++)
        {
            for (var col = 0; col < 7; col++)
            {
                var isOuter = row == 0 || row == 6 || col == 0 || col == 6;
                var isInner = row >= 2 && row <= 4 && col >= 2 && col <= 4;
                modules[rowStart + row, colStart + col] = isOuter || isInner;
            }
        }
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
