using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.Collections.Specialized;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class CommandHistoryPage : Page
{
    private readonly CommandHistoryViewModel _vm;

    public CommandHistoryPage()
    {
        InitializeComponent();
        _vm = new CommandHistoryViewModel(App.StateStore);

        FilterBox.ItemsSource = _vm.Filters;
        FilterBox.SelectedItem = _vm.SelectedFilter;
        CommandList.ItemsSource = _vm.Entries;
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

    private void OnSearchChanged(object sender, TextChangedEventArgs e)
    {
        _vm.SearchText = SearchBox.Text;
        Render();
    }

    private void HandleEntriesChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        Render();
    }

    private void Render()
    {
        var count = _vm.Entries.Count;
        ResultCountText.Text = $"{count} item{(count == 1 ? string.Empty : "s")} in view";
        EmptyStateText.Visibility = count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
}
