//! zig_tk: Python Tkinter風のZig向けGUIライブラリ。
//!
//!     const root = try tk.Tk.init(gpa);
//!     defer root.deinit();
//!     const btn = try tk.Button.init(root, .{ .text = "Click", .command = tk.callback(&app, App.onClick) });
//!     try btn.pack(.{ .side = .left, .padx = 4 });
//!     root.mainloop();

pub const tcl = @import("tcl.zig");

const interp_mod = @import("interp.zig");
pub const Interp = interp_mod.Interp;
pub const Error = interp_mod.Error;

const callback_mod = @import("callback.zig");
pub const Callback = callback_mod.Callback;
pub const EventCallback = callback_mod.EventCallback;
pub const ValidateCallback = callback_mod.ValidateCallback;
pub const Validation = callback_mod.Validation;
pub const Event = callback_mod.Event;
pub const callback = callback_mod.callback;
pub const callbackFn = callback_mod.callbackFn;

const widget_mod = @import("widget.zig");
pub const Widget = widget_mod.Widget;
pub const asWidget = widget_mod.asWidget;
pub const PackOptions = widget_mod.PackOptions;
pub const GridOptions = widget_mod.GridOptions;
pub const PlaceOptions = widget_mod.PlaceOptions;

const types = @import("types.zig");
pub const Side = types.Side;
pub const Fill = types.Fill;
pub const Anchor = types.Anchor;
pub const Relief = types.Relief;
pub const State = types.State;
pub const Justify = types.Justify;
pub const Orient = types.Orient;
pub const Compound = types.Compound;
pub const Sticky = types.Sticky;
pub const Validate = types.Validate;
pub const Padding = types.Padding;
pub const Index = types.Index;
pub const ListIndex = types.ListIndex;
pub const scroll = @import("scroll.zig");
/// items等がgpaで確保して返した文字列配列を解放する。
pub const freeStrings = @import("value.zig").freeStrings;

const variable = @import("variable.zig");
pub const Variable = variable.Variable;
pub const StringVar = variable.StringVar;
pub const IntVar = variable.IntVar;
pub const DoubleVar = variable.DoubleVar;
pub const BooleanVar = variable.BooleanVar;
pub const TraceMode = variable.TraceMode;
pub const TraceId = variable.TraceId;

pub const ttk = @import("ttk.zig");
pub const messagebox = @import("dialogs/messagebox.zig");
pub const filedialog = @import("dialogs/filedialog.zig");
pub const colorchooser = @import("dialogs/colorchooser.zig");
pub const font = @import("font.zig");
pub const PhotoImage = @import("image.zig").PhotoImage;
pub const Color = colorchooser.Color;
pub const TimerId = interp_mod.TimerId;

pub const Tk = @import("widgets/tk.zig").Tk;
pub const Button = @import("widgets/button.zig").Button;
pub const Label = @import("widgets/label.zig").Label;
pub const Frame = @import("widgets/frame.zig").Frame;
pub const Toplevel = @import("widgets/toplevel.zig").Toplevel;
pub const WmProtocol = @import("widgets/wm.zig").Protocol;
pub const Checkbutton = @import("widgets/checkbutton.zig").Checkbutton;
pub const CheckbuttonOf = @import("widgets/checkbutton.zig").CheckbuttonOf;
pub const Radiobutton = @import("widgets/radiobutton.zig").Radiobutton;
pub const RadiobuttonOf = @import("widgets/radiobutton.zig").RadiobuttonOf;
pub const Scale = @import("widgets/scale.zig").Scale;
pub const Spinbox = @import("widgets/spinbox.zig").Spinbox;
pub const Scrollbar = @import("widgets/scrollbar.zig").Scrollbar;
pub const Listbox = @import("widgets/listbox.zig").Listbox;
pub const Text = @import("widgets/text.zig").Text;
pub const Canvas = @import("widgets/canvas.zig").Canvas;
pub const Menu = @import("widgets/menu.zig").Menu;
pub const Entry = @import("widgets/entry.zig").Entry;
pub const LabelFrame = @import("widgets/labelframe.zig").LabelFrame;
pub const PanedWindow = @import("widgets/panedwindow.zig").PanedWindow;
pub const Message = @import("widgets/message.zig").Message;
pub const Menubutton = @import("widgets/menubutton.zig").Menubutton;
pub const OptionMenu = @import("widgets/optionmenu.zig").OptionMenu;
pub const OptionMenuOf = @import("widgets/optionmenu.zig").OptionMenuOf;

test {
    _ = @import("tests.zig");
    _ = @import("tests_inputs.zig");
    _ = @import("tests_scroll.zig");
    _ = @import("tests_text_canvas.zig");
    _ = @import("tests_notebook_treeview.zig");
    _ = @import("tests_menu_misc.zig");
    _ = @import("tests_layout.zig");
    _ = @import("tests_image.zig");
    _ = @import("tests_classic.zig");
}
