
include("EditorUtils.jl")

include("SearchWindow.jl")
include("Actions.jl")

extension(f::AbstractString) = splitext(f)[2]

sourcemap = nothing
if GtkSourceWidget.SOURCE_MAP
    sourcemap = eval( :(@GtkSourceMap()) )
else
    set_view() = nothing
end

global ntbook = @GtkNotebook()
    setproperty!(ntbook,:scrollable, true)
    setproperty!(ntbook,:enable_popup, true)

type EditorTab <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    view::GtkSourceView
    buffer::GtkSourceBuffer
    filename::AbstractString
    modified::Bool
    search_context::GtkSourceSearchContext
    search_mark
    scroll_target::AbstractFloat
    scroll_target_line::Integer

    function EditorTab(filename::AbstractString)

        lang = haskey(languageDefinitions,extension(filename)) ? languageDefinitions[extension(filename)] : languageDefinitions[".jl"]

        filename = isabspath(filename) ? filename : joinpath(pwd(),filename)
        filename = normpath(filename)

        b = @GtkSourceBuffer(lang)
        setproperty!(b,:style_scheme,style)
        v = @GtkSourceView(b)

        highlight_matching_brackets(b,true)

        show_line_numbers!(v,true)
	    auto_indent!(v,true)
        highlight_current_line!(v, true)
        setproperty!(v,:wrap_mode,0)

        setproperty!(v,:tab_width,4)
        setproperty!(v,:insert_spaces_instead_of_tabs,true)

        sc = @GtkScrolledWindow()
        push!(sc,v)

        search_con = @GtkSourceSearchContext(b,search_settings)
        highlight(search_con,true)

        t = new(sc.handle,v,b,filename,false,search_con,nothing)
        Gtk.gobject_move_ref(t, sc)
    end
    EditorTab() = EditorTab("")
end

function set_text!(t::EditorTab,text::AbstractString)
    setproperty!(t.buffer,:text,text)
end
get_text(t::EditorTab) = getproperty(t.buffer,:text,AbstractString)
getbuffer(textview::GtkTextView) = getproperty(textview,:buffer,GtkSourceBuffer)
get_current_tab() = get_tab(ntbook,get_current_page_idx(ntbook))

include("CompletionWindow.jl")

import Base.open
function open(t::EditorTab, filename::AbstractString)
    try
        if isfile(filename)
            f = Base.open(filename)
            set_text!(t,readall(f))
            t.modified = false
        else
            f = Base.open(filename,"w")
            t.modified = true
        end
        t.filename = filename
        set_tab_label_text(ntbook,t,basename(filename))
        reset_undomanager(t.buffer)#otherwise we can undo loading the file...
        close(f)
    catch err
        @show err
    end
    update!(project)
end

function save(t::EditorTab)
    try
        f = Base.open(t.filename,"w")
        write(f,get_text(t))
        write(console,"saved $(t.filename)\n")
        close(f)
        modified(t,false)
    catch err
        @show err
    end
end

save_current_tab() = save(get_current_tab())

function open_in_new_tab(filename::AbstractString)

    t = add_tab(filename)
    open(t,t.filename)

    return t
end

function set_font(t::EditorTab)
    sc = Gtk.G_.style_context(t.view)
    push!(sc, provider, 600)
end

function get_cell(buffer::GtkTextBuffer)
    (foundb,itb_start,itb_end) = text_iter_backward_search(buffer,"\n##")
    (foundf,itf_start,itf_end) = text_iter_forward_search(buffer,"\n##")

    if foundf && !foundb
        return(true, mutable(GtkTextIter(buffer,1)), itf_end) #start of file
    end

    return((foundf && foundb), itb_start, itf_end)
end

function highlight_cells()

    Gtk.apply_tag(srcbuffer, "background", GtkTextIter(srcbuffer,1) , GtkTextIter(srcbuffer,length(srcbuffer)+1) )
    (found,it_start,it_end) = get_cell(srcbuffer)

    if found
        Gtk.apply_tag(srcbuffer, "cell", it_start , it_end )
    end
end

function get_selected_text(t::EditorTab)
    (found,it_start,it_end) = selection_bounds(t.buffer)
    return found ? text_iter_get_text(it_start,it_end) : ""
end
get_selected_text() = get_selected_text(get_current_tab())

function ntbook_switch_page_cb(widgetptr::Ptr, pageptr::Ptr, pagenum::Int32, user_data)

    page = convert(Gtk.GtkWidget, pageptr)
    if typeof(page) == EditorTab && GtkSourceWidget.SOURCE_MAP
        set_view(sourcemap, page.view)
    end
    nothing
end
signal_connect(ntbook_switch_page_cb,ntbook, "switch-page", Void, (Ptr{Gtk.GtkWidget},Int32), false)

global mousepos = zeros(Int,2)
global mousepos_root = zeros(Int,2)
signal_connect(ntbook, "motion-notify-event") do widget, event, args...
    mousepos[1] = round(Int,event.x)
    mousepos[2] = round(Int,event.y)
    mousepos_root[1] = round(Int,event.x_root)
    mousepos_root[2] = round(Int,event.y_root)
end

function close_tab()
    idx = get_current_page_idx(ntbook)
    splice!(ntbook,idx)
    set_current_page_idx(ntbook,max(idx-1,0))
end


# FIXME need to take into account module
# set the cursos position ?
# check if the file is already open

function open_method(view::GtkTextView)

    word = get_word_under_mouse_cursor(view)

    try
        ex = parse(word)

        v = eval(Main,ex)
        v = typeof(v) == Function ? methods(v) : v

        tv, decls, file, line = Base.arg_decl_parts(v.defs)
        file = string(file)
        file = ispath(file) ? file : joinpath( joinpath(splitdir(JULIA_HOME)[1],"share/julia/base"), file)
        file = normpath(file)
        if ispath(file)
            #first look in existing tabs if the file is already open
            for i = 1:length(ntbook)
                n = ntbook[i]
                if typeof(n) == EditorTab && n.filename == file

                    set_current_page_idx(ntbook,i)
                    it = GtkTextIter(n.buffer,line,1)
                    scroll_to_iter(n.view, it)
                    text_buffer_place_cursor(n.buffer,it)
                    grab_focus(n.view)

                    return true
                end
            end
            #otherwise open it
            t = open_in_new_tab(file)
            t.scroll_target_line = line

            return true
        end
    catch 
        
    end
    return false
end

function line_to_adj_value(buffer::GtkTextBuffer,adj::GtkAdjustment,l::Integer)

    tot = line_count(buffer)
    scaling = getproperty(adj,:upper,AbstractFloat) -
              getproperty(adj,:page_size,AbstractFloat)

    return l/tot * scaling
end

#clicks
function tab_button_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)
    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    buffer = getproperty(textview,:buffer,GtkTextBuffer)

    if event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS

        (x,y) = text_view_window_to_buffer_coords(textview,mousepos[1],mousepos[2])
        iter_end = get_iter_at_position(textview,x,y)
        #iter_end = mutable( get_text_iter_at_cursor(buffer) ) #not using this because the cursor position is modified somewhere

        (w, iter_start, iter_end) = select_word(iter_end,buffer)

        selection_bounds(buffer,iter_start,iter_end)

        return convert(Cint,true)
    end

    if Int(event.button) == 1 && event.state == GdkModifierType.CONTROL #ctrl+right click
        open_method(textview) && return INTERRUPT
    end

    return PROPAGATE
end

function editor_autocomplete(view::GtkTextView,replace=true)

    buffer = getbuffer(view)

    (cmd,itstart,itend) = select_word_backward(get_text_iter_at_cursor(buffer),buffer,false)
    #@show (cmd,itstart,itend)

    if cmd == ""
        visible(completion_window,false)
        return convert(Cint, false)  #we go back to normal behavior if there's nothing on the left of the cursor
    end

    #(comp,dotpos) = completions(cmd, endof(cmd))
    #FIXME shouldn't parse each time
    (comp,dotpos) = extcompletions(cmd,collect_symbols(get_current_tab()))

    if isempty(comp)
        visible(completion_window,false)
        return convert(Cint, false)
    end

    #don't insert prefix when completing a method
    replace = (cmd[end] == '(' && length(comp)>1 ) ? false : replace

    dotpos_ = dotpos
    dotpos = dotpos.start
    prefix = dotpos > 1 ? cmd[1:dotpos-1] : "" #FIXME: redundant with the console code
    out = ""
    if(length(comp)>1)
        out = prefix * Base.LineEdit.common_prefix(comp)
        build_completion_window(comp,view,prefix)
    else
        out = prefix * comp[1]
        visible(completion_window) && build_completion_window(comp,view,prefix)
    end

    replace && insert_autocomplete(out,itstart,itend,buffer)

    return convert(Cint, true)
end

function replace_text(buffer::GtkTextBuffer,itstart::GtkTextIter,itend::GtkTextIter,str::AbstractString)
    pos = offset(itstart)+1
    text_buffer_delete(buffer,itstart,itend)
    insert!(buffer,GtkTextIter(buffer,pos),str)
end

# returns the position of the cursor inside a buffer such that we can position a window there
function get_cursor_absolute_position(view::GtkTextView)

    (it,r1,r2) = cursor_locations(view)
    (x,y) = text_view_buffer_to_window_coords(view,1,r1.x,r1.y)

    w = Gtk.G_.window(view)
    (ox,oy) = gdk_window_get_origin(w)

    return (x+ox, y+oy+r1.height,r1.height)

end

function run_line(buffer::GtkTextBuffer)

    cmd = get_selected_text()
    if cmd == ""
        (cmd, itstart, itend) = get_current_line_text(buffer)
        cmd = strip(cmd)
    end
    on_return_terminal(cmd,false)
end

function tab_key_release_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    buffer = getbuffer(textview)

    !update_completion_window_release(event,buffer) && return convert(Cint,true)

    return convert(Cint,false)#false : propagate
end

function tab_key_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    #note use write(console,...) here and not print or @show

    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    buffer = getbuffer(textview)
    t = user_data

    #write(console,string( event.state) * "\n" )
    #write(console,string( Actions.save.state) * "\n" )

    if doing(Actions.save, event)
        save_current_tab()
    end
    if doing(Actions.closetab, event)
        close_tab()
        save(project)
    end
    if doing(Actions.newtab, event)
        add_tab()
        save(project)
    end
    if doing(Actions.datahint, event)
        show_data_hint(textview)
    end
    if doing(Actions.search, event)
        open(search_window)
    end
    if event.keyval == Gtk.GdkKeySyms.Tab
        if !visible(completion_window)
            return editor_autocomplete(textview)
        end
    end
    if doing(Actions.runline, event)

        run_line(buffer)
        return convert(Cint,true)
    end
    if doing(Actions.runcode, event)

        cmd = get_selected_text()
        if cmd == ""
            (found,it_start,it_end) = get_cell(buffer)
            if found
                cmd = text_iter_get_text(it_start,it_end)
            else
                cmd = getproperty(buffer,:text,AbstractString)
            end
        end
        on_return_terminal(cmd,false)
        return convert(Cint,true)
    end
    if doing(Actions.runfile, event)
        cmd = "include(\"$(t.filename)\")"
        cmd = replace(cmd,"\\", "/")
        setproperty!(console.entry,:text,cmd)
        on_return_terminal(cmd,true)
    end

    !update_completion_window(event,buffer) && return convert(Cint,true)

    return convert(Cint,false)#false : propagate
end

function get_word_under_mouse_cursor(textview::GtkTextView)

    (x,y) = text_view_window_to_buffer_coords(textview,mousepos[1],mousepos[2])
    iter_end = get_iter_at_position(textview,x,y)
    buffer = getproperty(textview,:buffer,GtkTextBuffer)
    (word,itstart,itend) = select_word(iter_end,buffer,false)

    return word
end

function show_data_hint(textview::GtkTextView)

    word = get_word_under_mouse_cursor(textview)

    try
      ex = parse(word)
      value = eval(Main,ex)
      value = typeof(value) == Function ? methods(value) : value
      value = sprint(Base.showlimited,value)

      label = @GtkLabel(value)
      popup = @GtkWindow("", 2, 2, true, false) |> label
      setproperty!(label,:margin,5)

      Gtk.G_.position(popup,mousepos_root[1]+10,mousepos_root[2])
      showall(popup)

      @schedule begin
          sleep(2)
          destroy(popup)
      end

    end
end

value(adj::GtkAdjustment) = getproperty(adj,:value,AbstractFloat)
value(adj::GtkAdjustment,v::AbstractFloat) = setproperty!(adj,:value,v)

# maybe I should replace this by a task that check for the
# end of loading and then call a function
function tab_adj_changed_cb(adjptr::Ptr, user_data)

    #FIXME need to check if the scroll target is valid somehow
    adj = convert(GtkAdjustment, adjptr)
    t = user_data
    if t.scroll_target != 0 && t.scroll_target_line == 0
        if value(adj) != t.scroll_target
            value(adj,t.scroll_target)
        else
            t.scroll_target = 0
        end
    end

    if t.scroll_target_line != 0
        v = line_to_adj_value(get_buffer(t.view),adj,t.scroll_target_line)
        if value(adj) != v
            value(adj,v)
        else
            t.scroll_target_line = 0
        end
    end

    return nothing
end

function tab_extend_selection_cb(widgetptr::Ptr,granularityptr::Ptr,locationptr::Ptr,it_startptr::Ptr,it_endptr::Ptr,user_data)

    view = convert(GtkTextView,widgetptr)
    location = convert(GtkTextView,locationptr)

    return convert(Cint,false)
end

function modified(t::EditorTab,v::Bool)
    t.modified = v
    s = v ? basename(t.filename) * "*" : basename(t.filename)
    set_tab_label_text(ntbook,t,s)
end

function tab_buffer_changed_cb(widgetptr::Ptr,user_data)
    t = user_data
    modified(t,true)

    return nothing
end

function add_tab(filename::AbstractString)
    t = EditorTab(filename);
    t.scroll_target = 0.
    t.scroll_target_line = 0

    idx = get_current_page_idx(ntbook)+1
    insert!(ntbook, idx, t, "Page $idx")
    showall(ntbook)
    set_current_page_idx(ntbook,idx)

    Gtk.create_tag(t.buffer, "debug1", font="Normal $fontsize",background="green")
    Gtk.create_tag(t.buffer, "debug2", font="Normal $fontsize",background="blue")
    set_font(t)

    signal_connect(tab_key_press_cb,t.view, "key-press-event", Cint, (Ptr{Gtk.GdkEvent},), false,t) #we need to use the view here to capture all the keystrokes
    signal_connect(tab_key_release_cb,t.view, "key-release-event", Cint, (Ptr{Gtk.GdkEvent},), false)
    signal_connect(tab_button_press_cb,t.view, "button-press-event", Cint, (Ptr{Gtk.GdkEvent},), false)

    signal_connect(tab_buffer_changed_cb,t.buffer,"changed", Void, (), false,t)

    #signal_connect(tab_extend_selection_cb,t.view, "extend-selection", Cint, (Ptr{Void},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter},Ptr{Gtk.GtkTextIter}), false)

    signal_connect(tab_adj_changed_cb, getproperty(t.view,:vadjustment,GtkAdjustment) , "changed", Void, (), false,t)

    return t
end
add_tab() = add_tab("untitled")

function load_tabs(project::Project)

    #project get modified later
    files = project.files
    scroll_position = project.scroll_position
    ntbook_idx = project.ntbook_idx

    for i = 1:length(files)
        t = open_in_new_tab(files[i])
        t.scroll_target = scroll_position[i]
    end

    if length(ntbook)==0
        open_in_new_tab(joinpath(Pkg.dir(),"GtkIDE","README.md"))
    elseif ntbook_idx <= length(ntbook)
        set_current_page_idx(ntbook,ntbook_idx)
    end
    t = get_current_tab()
    GtkSourceWidget.SOURCE_MAP && set_view(sourcemap,t.view)
end

load_tabs(project)

# for i = 1:2
#     add_tab()
# end

##open(get_tab(ntbook,1),"d:\\Julia\\JuliaIDE\\repl.jl")

# set_text!(get_tab(ntbook,2),
# "
# function f(x)
#     x
# end
#
# ## ploting sin
#
# 	x = 0:0.01:5
# 	plot(x,exp(-x))
#
# ## ploting a spiral
#
# 	x = 0:0.01:4*pi
# 	plot(x.*cos(x),x.*sin(x))
#
# ##
#     x = 0:0.01:3*pi
#     for i=1:100
#         plot(x.*cos(i/15*x),x.*sin(i/10*x),
#             xrange=(-8,8),
#             yrange=(-8,8)
#         )
#         drawnow()
#     end
# ##
# ")
# end
# ##
# ")
