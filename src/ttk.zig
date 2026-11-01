//! テーマ付きウィジェット(Python tkinter.ttk相当)。
const common = @import("ttk/common.zig");
pub const StateFlag = common.StateFlag;
pub const StateSpec = common.StateSpec;

pub const Button = @import("ttk/button.zig").Button;
pub const Label = @import("ttk/label.zig").Label;
pub const Entry = @import("ttk/entry.zig").Entry;
pub const Panedwindow = @import("ttk/panedwindow.zig").Panedwindow;
pub const Checkbutton = @import("ttk/checkbutton.zig").Checkbutton;
pub const CheckbuttonOf = @import("ttk/checkbutton.zig").CheckbuttonOf;
pub const Radiobutton = @import("ttk/radiobutton.zig").Radiobutton;
pub const RadiobuttonOf = @import("ttk/radiobutton.zig").RadiobuttonOf;
pub const Scale = @import("ttk/scale.zig").Scale;
pub const Spinbox = @import("ttk/spinbox.zig").Spinbox;
pub const Combobox = @import("ttk/combobox.zig").Combobox;
pub const Scrollbar = @import("ttk/scrollbar.zig").Scrollbar;
pub const Notebook = @import("ttk/notebook.zig").Notebook;
pub const Treeview = @import("ttk/treeview.zig").Treeview;
pub const Frame = @import("ttk/frame.zig").Frame;
pub const Labelframe = @import("ttk/labelframe.zig").Labelframe;
pub const Separator = @import("ttk/separator.zig").Separator;
pub const Progressbar = @import("ttk/progressbar.zig").Progressbar;
pub const Style = @import("ttk/style.zig").Style;
pub const StyleOptions = @import("ttk/style.zig").StyleOptions;
pub const StateValue = @import("ttk/style.zig").StateValue;
pub const Menubutton = @import("ttk/menubutton.zig").Menubutton;

/// Python tkinter.ttk と同じ別名。
pub const LabelFrame = Labelframe;
pub const PanedWindow = Panedwindow;
