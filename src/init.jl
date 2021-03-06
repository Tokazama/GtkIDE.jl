## globals

function __init__()

    global const is_running = true #should probably use g_main_loop_is_running or something of the sort

    global const default_settings = init_opt()
    
    global const main_window = MainWindow()

    ## Console

    console_mng = ConsoleManager(main_window)
    init!(console_mng)

    ## Editor

    editor = Editor(main_window)

    search_window = SearchWindow(editor)
    init!(search_window)
    visible(search_window,false)

    init!(editor,search_window)

    upgrade_project()

    global const project = Project(main_window,"default")

    pathCBox = PathComboBox(main_window)
    statusBar = GtkStatusbar()

    menubar = MainMenu(main_window)

    global const sidepanel_ntbook = GtkNotebook()

    init!(main_window,editor,console_mng,pathCBox,statusBar,project,menubar,sidepanel_ntbook)

    load(project)
    cd(project.path)
    load_tabs(editor,project)

    ## Ploting window

    global const fig_ntbook = GtkNotebook()
    global const _display = Immerse._display

    #FIXME need init!
    signal_connect(fig_ntbook_key_press_cb,fig_ntbook, "key-press-event",Cint, (Ptr{Gtk.GdkEvent},), false)
    signal_connect(fig_ntbook_switch_page_cb,fig_ntbook,"switch-page", Void, (Ptr{Gtk.GtkWidget},Int32), false)

    ## completion window

    global const completion_window = CompletionWindow(main_window)
    visible(completion_window,false)

    ## Main layout
    global const mainPan = GtkPaned(:h)
    rightPan = GtkPaned(:v)

    main_window |>
        ((mainVbox = GtkBox(:v)) |>
            menubar |>
            (topBarBox = GtkBox(:h) |>
                (sidePanelButton = GtkButton("F1")) |>
                 pathCBox   |>
                (editorButton = GtkButton("F2"))
            ) |>
            (global const sidePan = GtkPaned(:h)) |>
            statusBar
        )

    mainPan |>
        (rightPan |>
            #(canvas = GtkCanvas())  |>
            (fig_ntbook)  |>
            console_mng
        ) |>
        ((editorVBox = GtkBox(:v)) |>
            ((editorBox = GtkBox(:h)) |>
                editor |>
                editor.sourcemap
            ) |>
            search_window
        )

    sidePan |>
        sidepanel_ntbook |>
        mainPan

    # Console

    console = first_console(main_window)
    #add_console()
    for i=1:length(free_workers(console_mng))
        add_console(main_window)
    end

    setproperty!(statusBar,:margin,2)
    GtkExtensions.text(statusBar,"Julia $VERSION")
    Gtk.G_.position(sidePan,160)

    setproperty!(editor,:vexpand,true)
    setproperty!(editorBox,:expand,editor,true)
    setproperty!(mainPan,:margin,0)
    Gtk.G_.position(mainPan,600)
    Gtk.G_.position(rightPan,450)
    #-

    ## set some style

    nbtbookcss =
    "* tab {
        padding:0px;
        padding-left:6px;
        padding-right:1px;
        margin:0px;
        font-size:$(main_window.style_and_language_manager.fontsize-1)px;
    }"
    style_css(main_window.editor,nbtbookcss)
    style_css(main_window.console_manager,nbtbookcss)
    style_css(fig_ntbook,nbtbookcss)
    style_css(sidepanel_ntbook,nbtbookcss)

    setproperty!(topBarBox,:hexpand,true)

    ################
    # Side Panels

    global const filespanel = FilesPanel(main_window)
    update!(filespanel)
    add_side_panel(filespanel,"F")

    global const workspacepanel = WorkspacePanel(main_window)
    update!(workspacepanel)
    add_side_panel(workspacepanel,"W")

    ##

    global const projectspanel = ProjectsPanel(main_window)
    update!(projectspanel)
    add_side_panel(projectspanel,"P")


    ################
    ## Plots

    sleep(0.01)
    figure()
    drawnow() = sleep(0.001)

    init!(pathCBox)#need on_path_change to be defined

    signal_connect(sidePanelButton_clicked_cb, sidePanelButton, "clicked", Void, (), false)
    signal_connect(editorButtonclicked_cb, editorButton, "clicked", Void, (), false)

    showall(main_window)
    visible(search_window,false)
    visible(sidepanel_ntbook,false)
    GtkSourceWidget.SOURCE_MAP && visible(editor.sourcemap,opt("Editor","show_source_map"))

    ## starting task and such

    sleep(0.01)

    if REDIRECT_STDOUT

        global const stdout = STDOUT
        global const stderr = STDERR

        read_stdout, wr = redirect_stdout()
        #read_stderr, wre = redirect_stderr()

        function watch_stdout()
            @schedule watch_stream(read_stdout,console)
        end
        function watch_stderr()
            @schedule watch_stream(read_stderr,console)
        end

        global const watch_stdout_task = watch_stdout()
        #global watch_stderr_task = watch_stderr()

        init_stdout!(main_window.console_manager,watch_stdout_task,stdout,stderr)

        g_timeout_add(10,print_to_console,console)
    end

    println("Warming up, hold on...")
    sleep(0.05)
    @schedule logo()
    new_prompt(console)

end