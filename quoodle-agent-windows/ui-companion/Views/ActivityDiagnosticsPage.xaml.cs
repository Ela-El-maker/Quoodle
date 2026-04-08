using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.Collections.Specialized;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class ActivityDiagnosticsPage : Page
{
    private readonly ActivityDiagnosticsViewModel _vm;

    public ActivityDiagnosticsPage()
    {
        InitializeComponent();
        _vm = new ActivityDiagnosticsViewModel(App.StateStore);

        FilterBox.ItemsSource = _vm.Filters;
        FilterBox.SelectedItem = _vm.SelectedFilter;
        ActivityList.ItemsSource = _vm.Entries;
        _vm.Entries.CollectionChanged += HandleEntriesChanged;
        Render();
    }

    private void OnFilterChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FilterBox.SelectedItem is string selected)
        {
            _vm.SelectedFilter = selected;
            Render();
        }
    }

    private void HandleEntriesChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        Render();
    }

    private void Render()
    {
        TabCountText.Text = _vm.Entries.Count.ToString();
    }
}
