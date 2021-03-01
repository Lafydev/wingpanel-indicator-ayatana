/*
 * Copyright (c) 2011-2015 Wingpanel Developers (http://launchpad.net/wingpanel)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street - Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

public class AyatanaCompatibility.Indicator : Wingpanel.Indicator {
    private IndicatorButton icon;

    private Gtk.Stack main_stack;
    private Gtk.ListBox main_list;

    private unowned IndicatorAyatana.ObjectEntry entry;
    private unowned IndicatorAyatana.Object parent_object;
    private IndicatorIface indicator;
    private string entry_name_hint;

    //maps to help dynamic changes in menus and submenus
    private Gee.HashMap<Gtk.Widget, Gtk.Widget> menu_map;
	private Gee.HashMap<Gtk.Widget, Gtk.Widget> submenu_map;
	
    const int MAX_ICON_SIZE = 20;
    
	//grouping radio buttons
	private Gtk.RadioButton? group_radio=null ;
	
    public Indicator (IndicatorAyatana.ObjectEntry entry, IndicatorAyatana.Object obj, IndicatorIface indicator) {
        string name_hint = entry.name_hint;
        if (name_hint == null) {
            var current_time = new DateTime.now_local ();
            name_hint = current_time.hash ().to_string ();
        }

        Object (code_name: "%s%s".printf ("ayatana-", name_hint));
        this.entry = entry;
        this.indicator = indicator;
        this.parent_object = obj;
        this.menu_map = new Gee.HashMap<Gtk.Widget, Gtk.Widget> ();
        entry_name_hint = name_hint;

        if (entry.menu == null) {
            critical ("Indicator: %s has no menu widget.", entry_name_hint);
            return;
        }

        /*
         * Workaround for buggy indicators: this menu may still be part of
         * another panel entry which hasn't been destroyed yet. Those indicators
         * trigger entry-removed after entry-added, which means that the previous
         * parent is still in the panel when the new one is added.
         */
        if (entry.menu.get_attach_widget () != null) {
            entry.menu.detach ();
        }

        this.visible = true;
    }

    public override Gtk.Widget get_display_widget () {
		//show an icon in the panel
        if (icon == null) {
            icon = new IndicatorButton ();

            var image = entry.image as Gtk.Image;

            if (image != null) {
                /*
                 * images holding pixbufs are quite frequently way too large, so we whenever a pixbuf
                 * is assigned to an image we need to check whether this pixbuf is within reasonable size
                 */
                if (image.storage_type == Gtk.ImageType.PIXBUF) {
                    image.notify["pixbuf"].connect (() => {
                        ensure_max_size (image);
                    });

                    ensure_max_size (image);
                }

                image.pixel_size = MAX_ICON_SIZE;

                icon.set_widget (IndicatorButton.WidgetSlot.IMAGE, image);
            }

            var label = entry.label;

            if (label != null && label is Gtk.Label) {
                icon.set_widget (IndicatorButton.WidgetSlot.LABEL, label);
            }

            icon.scroll_event.connect (on_scroll);
            icon.button_press_event.connect (on_button_press);
        }

        return icon;
    }

    public string name_hint () {
        return entry_name_hint;
    }

    public bool on_button_press (Gdk.EventButton event) {
        if (event.button == Gdk.BUTTON_MIDDLE) {
            parent_object.secondary_activate (entry, event.time);

            return Gdk.EVENT_STOP;
        }

        return Gdk.EVENT_PROPAGATE;
    }

    public bool on_scroll (Gdk.EventScroll event) {
        parent_object.entry_scrolled (entry, 1, (IndicatorAyatana.ScrollDirection)event.direction);

        return Gdk.EVENT_PROPAGATE;
    }

    public override Gtk.Widget? get_widget () {
        if (main_stack == null) {
            bool reloaded = false;
            icon.parent.parent.enter_notify_event.connect ((w, e) => {
                if (!reloaded && e.mode != Gdk.CrossingMode.TOUCH_BEGIN) {
                    /*
                     * workaround for indicators (e.g. dropbox) that only update menu children after
                     * the menu is popuped
                     */
                    reloaded = true;
                    //show underlying menu (debug)
                    //entry.menu.popup_at_widget(icon.parent,0,0);
                    //entry.menu.popdown ();
                }

                return Gdk.EVENT_PROPAGATE;
            });

            main_stack = new Gtk.Stack ();
            main_stack.map.connect (() => {
				//reload: open first on main_list
                main_stack.set_visible_child (main_list);
                reloaded = false;
            });
            main_list = new Gtk.ListBox();
            main_list.set_size_request(230,-1);
            main_stack.add (main_list);

            foreach (var item in entry.menu.get_children ()) {
                on_menu_widget_insert (item);
            }

            entry.menu.insert.connect (on_menu_widget_insert);
            entry.menu.remove.connect (on_menu_widget_remove);
        }

        return main_stack;
    }

    private void on_menu_widget_insert (Gtk.Widget item) {
        var w = convert_menu_widget (item);

        if (w != null) {
            menu_map.set (item, w);
            main_list.add (w);
            /* menuitem not visible */
            if (!item.get_visible ()) {
                w.no_show_all = true;
                w.hide ();
            } else {
                w.show ();
            }
        }
    }

    private void on_menu_widget_remove (Gtk.Widget item) {
        var w = menu_map.get (item);

        if (w != null) {
            main_list.remove (w);
            menu_map.unset (item);
        }
    }

    private Gtk.Image? check_for_image (Gtk.Container container) {
        foreach (var c in container.get_children ()) {
            if (c is Gtk.Image) {
                return (c as Gtk.Image);
            } else if (c is Gtk.Container) {
                return check_for_image ((c as Gtk.Container));
            }
        }

        return null;
    }

    private void connect_signals (Gtk.Widget item, Gtk.Widget button) {
        item.show.connect (() => {
            button.no_show_all = false;
            button.show ();
        });
        item.hide.connect (() => {
            button.no_show_all = true;
            button.hide ();
        });
		item.state_flags_changed.connect  ((type) => {
           button.set_state_flags (item.get_state_flags (),true);
        });
    }

    /* convert the menuitems to widgets that can be shown in popovers */
    private Gtk.Widget? convert_menu_widget (Gtk.Widget item) {
        /* separator are GTK.SeparatorMenuItem, return a separator */
        if (item is Gtk.SeparatorMenuItem) {
            var separator =  new Wingpanel.Widgets.Separator ();

            connect_signals (item, separator);
			group_radio = null; 
            return separator;
        }

        /* all other items are genericmenuitems */
        string label = (item as Gtk.MenuItem).get_label ();
        label = label.replace ("_", "");

        /*
         * get item type from atk accessibility
         * 34 = MENU_ITEM  8 = CHECKBOX  32 = SUBMENU 44 = RADIO
         */
        const int ATK_CHECKBOX =8;
		const int ATK_RADIO =44;
		
        var atk = item.get_accessible ();
        Value val = Value (typeof (int));
        atk.get_property ("accessible_role", ref val);
        var item_type = val.get_int ();

        var state = item.get_state_flags ();
        // concern radiobuttons too 
        var active = (item as Gtk.CheckMenuItem).get_active ();
		//RAZ group_radio
        group_radio = ( item_type == ATK_RADIO)? group_radio:null;
		
        /* detect if it has a image */
        Gtk.Image? image = null;
        var child = (item as Gtk.Bin).get_child ();

        if (child != null) {
            if (child is Gtk.Image) {
                image = (child as Gtk.Image);
            } else if (child is Gtk.Container) {
                image = check_for_image ((child as Gtk.Container));
            }
        }

        if (item_type == ATK_CHECKBOX) {
            var button = new Wingpanel.Widgets.Switch (label, active);
            // b=bool
            button.get_switch ().state_set.connect ((b) => {
                (item as Gtk.CheckMenuItem).set_active (b);
                close ();
                return false;
            });
            button.set_state_flags(state,false);
            
            connect_signals (item, button);
            (item as Gtk.CheckMenuItem).toggled.connect (() => {
                button.active = ((item as Gtk.CheckMenuItem).get_active ());
            });

            return button;
        }

        //RADIO BUTTON
		if (item_type == ATK_RADIO) {
			var button= new Gtk.RadioButton.with_label_from_widget(group_radio,label);
			if (group_radio==null) {group_radio=button;}
			button.margin = 5;
            button.set_margin_start(10);
			button.set_active(active);
			
			button.clicked.connect (() => {
                    item.activate ();
                });
           //concern only visible underlying menu (debug) 
           /* if (item.get_visible ()) {
				(item as Gtk.CheckMenuItem).toggled.connect (() => {
					button.active = (item as Gtk.CheckMenuItem).get_active ();
				});
            } */
			
			return button;
		}
		
        /* convert menuitem to a indicatorbutton */
        if (item is Gtk.MenuItem) {
			Gtk.ModelButton button;
            if (image != null && image.pixbuf == null && image.icon_name != null) {
                try {
                    Gtk.IconTheme icon_theme = Gtk.IconTheme.get_default ();
                    image.pixbuf = icon_theme.load_icon (image.icon_name, 16, 0);
                } catch (Error e) {
                    warning (e.message);
                }
            }
            button = new Gtk.ModelButton();
            button.text=label;
			if (image != null && image.pixbuf != null) {
                (button as Gtk.ModelButton).icon= (image.pixbuf);
            } 
            if (item_type == ATK_RADIO) {
				button.role=Gtk.ButtonRole.RADIO;
				button.active = (item as Gtk.RadioMenuItem).get_active ();
			}
            (item as Gtk.CheckMenuItem).notify["label"].connect (() => {
                (button as Gtk.ModelButton).text= ((item as Gtk.MenuItem).get_label ().replace ("_", ""));
            });

			button.set_state_flags(state,true); 
			
            var submenu = (item as Gtk.MenuItem).submenu;

            if (submenu != null) {
                var scroll_sub = new Gtk.ScrolledWindow (null, null);
                scroll_sub.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
                var sub_list = new Gtk.ListBox ();
                scroll_sub.add (sub_list);
                //btn back
				var btn_back = new Gtk.ModelButton();
				btn_back.text= _("Back");
				btn_back.inverted=true;
				btn_back.menu_name="main_list";
				btn_back.clicked.connect(()=>{
					main_stack.set_visible_child (main_list);
				});
				sub_list.add(btn_back);
                //convert
                foreach (var sub_item in submenu.get_children ()) {
					var sub_menu_item = convert_menu_widget (sub_item);
					connect_signals (sub_item, sub_menu_item);
					sub_list.add (sub_menu_item);
				}
				//dynamic change at run time
				submenu.insert.connect ((item) => {
				  var w = convert_menu_widget (item);

        		  if (w != null) {
            			submenu_map.set (item, w);
						sub_list.add(w);
        			}
				});
				submenu.remove.connect ((item)=> {
					var w = menu_map.get (item);

        			if (w != null) {
            			sub_list.remove (w);
            			submenu_map.unset (item);
        			}	
				});
                main_stack.add (scroll_sub);
                
                //modelbutton for popup
				button = new Gtk.ModelButton();
                button.text= label; 
                button.menu_name="submenu";
                
                button.clicked.connect (() => {
                    main_stack.set_visible_child (scroll_sub);
                    main_stack.show_all ();
                });
            } else {
                button.clicked.connect (() => {
                    close ();
                    item.activate ();
                });
            }

            connect_signals (item, button);

            return button;
        }

        return null;
    }

    public override void opened () {
    }

    public override void closed () {
    }

    private void ensure_max_size (Gtk.Image image) {
        var pixbuf = image.pixbuf;

        if (pixbuf != null && pixbuf.get_height () != MAX_ICON_SIZE) {
			//scale_simple(dest_width,dest_height,interp)
            image.pixbuf = pixbuf.scale_simple (
                (int)((double)MAX_ICON_SIZE / pixbuf.get_height () * pixbuf.get_width ()),
            	MAX_ICON_SIZE, Gdk.InterpType.HYPER);
        }
    }
}
