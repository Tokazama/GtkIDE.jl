# module GtkExtenstions
#
# export text_iter_get_text, text_iter_forward_line, text_iter_backward_line, text_iter_forward_to_line_end, text_iter_forward_word_end,
# 	   text_iter_backward_word_start, text_iter_forward_search, text_iter_backward_search, show_iter,
# 	   text_buffer_place_cursor, get_iter_at_position, text_view_window_to_buffer_coords, get_current_page_idx,
# 	   set_current_page_idx, get_tab, set_position!, text_buffer_copy_clipboard, set_tab_label_text
#
# using Gtk
# const libgtk = Gtk.Gtk.libgtk

baremodule GdkModifierType
    const SHIFT		= Main.Base.convert(Int32,1)
    const LOCK 	  	= Main.Base.convert(Int32,2)
	const CONTROL 	= Main.Base.convert(Int32,4)
end

typealias MutableGtkTextIter Gtk.GLib.MutableTypes.Mutable{Gtk.GtkTextIter}
typealias GtkTextIters Union{MutableGtkTextIter,Gtk.GtkTextIter}
mutable(it::Gtk.GtkTextIter) = Gtk.GLib.MutableTypes.mutable(it)

function text_iter_get_text(it_start::GtkTextIters,it_end::GtkTextIters)
	s = ccall((:gtk_text_iter_get_text,Gtk.libgtk),Ptr{Uint8},(Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter}),it_start,it_end)
	return s == C_NULL ? "" : bytestring(s)
end

text_iter_forward_line(it::MutableGtkTextIter)  = ccall((:gtk_text_iter_forward_line,  Gtk.libgtk),Cint,(Ptr{Gtk.GtkTextIter},),it)
text_iter_backward_line(it::MutableGtkTextIter) = ccall((:gtk_text_iter_backward_line, Gtk.libgtk),Cint,(Ptr{Gtk.GtkTextIter},),it)
text_iter_forward_to_line_end(it::MutableGtkTextIter) = ccall((:gtk_text_iter_forward_to_line_end, Gtk.libgtk),Cint,(Ptr{Gtk.GtkTextIter},),it)

text_iter_forward_word_end(it::MutableGtkTextIter) = ccall((:gtk_text_iter_forward_word_end, Gtk.libgtk),Cint,(Ptr{Gtk.GtkTextIter},),it)
text_iter_backward_word_start(it::MutableGtkTextIter) = ccall((:gtk_text_iter_backward_word_start, Gtk.libgtk),Cint,(Ptr{Gtk.GtkTextIter},),it)

text_iter_forward_search(it::MutableGtkTextIter, txt::String, start::MutableGtkTextIter, stop::MutableGtkTextIter, limit::MutableGtkTextIter) = ccall((:gtk_text_iter_forward_search, Gtk.libgtk),
  Cint,
  (Ptr{Gtk.GtkTextIter},Ptr{Uint8},Cint,Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter}),
  it,bytestring(txt),Int32(2),start,stop,limit
)
function text_iter_forward_search(buffer::GtkTextBuffer, txt::String)
  its = mutable(Gtk.GtkTextIter(buffer))
  ite = mutable(Gtk.GtkTextIter(buffer))
  found = text_iter_forward_search(mutable( Gtk.GtkTextIter(buffer,getproperty(buffer,:cursor_position,Int))),txt,its,ite,mutable(Gtk.GtkTextIter(buffer,length(buffer))))

  return (found,its,ite)
end

text_iter_backward_search(it::MutableGtkTextIter, txt::String, start::MutableGtkTextIter, stop::MutableGtkTextIter, limit::MutableGtkTextIter) = ccall((:gtk_text_iter_backward_search, Gtk.libgtk),
  Cint,
  (Ptr{Gtk.GtkTextIter},Ptr{Uint8},Cint,Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter}),
  it,bytestring(txt),Int32(2),start,stop,limit
)
function text_iter_backward_search(buffer::GtkTextBuffer, txt::String)
  its = mutable(Gtk.GtkTextIter(buffer))
  ite = mutable(Gtk.GtkTextIter(buffer))
  found = text_iter_backward_search(mutable( Gtk.GtkTextIter(buffer,getproperty(buffer,:cursor_position,Int))),txt,its,ite,mutable(Gtk.GtkTextIter(buffer,1)))

  return (found,its,ite)
end

function show_iter(it::MutableGtkTextIter,buffer::GtkTextBuffer,color::Int)
    Gtk.apply_tag(buffer, color > 0 ? "debug1" : "debug2",it, it+1)
end

text_buffer_place_cursor(buffer::GtkTextBuffer,it::MutableGtkTextIter)  = ccall((:gtk_text_buffer_place_cursor,  Gtk.libgtk),Void,(Ptr{Gtk.GObject},Ptr{Gtk.GtkTextIter}),buffer,it)
text_buffer_place_cursor(buffer::GtkTextBuffer,pos::Int) = text_buffer_place_cursor(srcbuffer,mutable(Gtk.GtkTextIter(srcbuffer,pos)))
text_buffer_place_cursor(buffer::GtkTextBuffer,it::Gtk.GtkTextIter) = text_buffer_place_cursor(srcbuffer,mutable(it))

get_iter_at_position(text_view::Gtk.GtkTextView,iter::MutableGtkTextIter,trailing,x::Int32,y::Int32) = ccall((:gtk_text_view_get_iter_at_position,Gtk.libgtk),Void,
	(Ptr{Gtk.GObject},Ptr{Gtk.GtkTextIter},Ptr{Cint},Cint,Cint),text_view,iter,trailing,x,y)

function get_iter_at_position(text_view::Gtk.GtkTextView,x::Integer,y::Integer)
	 iter = mutable(Gtk.GtkTextIter(getproperty(text_view,:buffer,GtkTextBuffer)))
	 get_iter_at_position(text_view::Gtk.GtkTextView,iter,C_NULL,Int32(x),Int32(y))
	 return iter
end

function text_view_window_to_buffer_coords(text_view::Gtk.GtkTextView,wintype::Int,window_x::Int,window_y::Int)

	buffer_x = Gtk.mutable(Cint)
	buffer_y = Gtk.mutable(Cint)

	ccall((:gtk_text_view_window_to_buffer_coords,Gtk.libgtk),Void,
		(Ptr{Gtk.GObject},Cint,Cint,Cint,Ptr{Cint},Ptr{Cint}),text_view,Int32(wintype),window_x,window_y,buffer_x,buffer_y)

	return (buffer_x[],buffer_y[])
end

text_view_window_to_buffer_coords(text_view::Gtk.GtkTextView,window_x::Int,window_y::Int) = text_view_window_to_buffer_coords(text_view,2,window_x,window_y)

# notebook things
get_current_page_idx(notebook::Gtk.GtkNotebook) = ccall((:gtk_notebook_get_current_page,Gtk.libgtk),Cint,
    (Ptr{Gtk.GObject},),notebook)+1 #+1 so it works with splice!

set_current_page_idx(notebook::Gtk.GtkNotebook,page_num::Int) = ccall((:gtk_notebook_set_current_page,Gtk.libgtk),Void,
    (Ptr{Gtk.GObject},Cint),notebook,page_num-1)

get_tab(notebook::Gtk.GtkNotebook,page_num::Int) = convert(Gtk.GtkWidget,ccall((:gtk_notebook_get_nth_page,Gtk.libgtk),Ptr{Gtk.GObject},
	(Ptr{Gtk.GObject},Cint),notebook,page_num-1))

set_tab_label_text(notebook::Gtk.GtkNotebook,child,tab_text) = ccall((:gtk_notebook_set_tab_label_text,Gtk.Gtk.libgtk),Void,(Ptr{Gtk.GObject},
Ptr{Gtk.GObject},Ptr{Uint8}),notebook,child,tab_text)


## entry

function set_position!(editable::Gtk.Entry,position_)
    ccall((:gtk_editable_set_position,Gtk.Gtk.libgtk),Void,(Ptr{Gtk.GObject},Cint),editable,position_)
end

## clipboard

text_buffer_copy_clipboard(buffer::GtkTextBuffer,clip::GtkClipboard)  = ccall((:gtk_text_buffer_copy_clipboard,  Gtk.Gtk.libgtk),Void,
    (Ptr{GObject},Ptr{GObject}),buffer,clip)

#end#module
