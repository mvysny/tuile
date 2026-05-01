# Specification for adding a scroll bar to Component::List (or List for short)

List needs to have an optional scroll bar. It will consist of these characters:

* `█` for the handle (filled track)
* `░` for the slider (empty track)

There are no up/down buttons displayed.

The scrollbar is implemented in vertical_scroll_bar.rb, in the VerticalScrollBar class.

The visibility of the scroll bar is controlled by a property `List.scrollbar_visibility` with the following values:

* `:gone` - no scrollbar shown
* `:visible` - scrollbar visible at all times

Corner cases:
* When the component is one row tall and scrollbar needs to be drawn, only draw the handle track character.

Example of how List should look like when it's 10 lines tall, there are 20 items, and the last 10 items are shown:

```
Item 11   ░
Item 12   ░
Item 13   ░
Item 14   ░
Item 15   ░
Item 16   █
Item 17   █
Item 18   █
Item 19   █
Item 20   █
```
