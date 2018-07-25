#= require_self
#= require_tree ./editor
Mousetrap.stopCallback = (e, element, combo) ->

  # stop for input, select, and textarea
  element.tagName is "INPUT" or element.tagName is "SELECT" or element.tagName is "TEXTAREA"

class @Editor
  # options:
  #   editable - selector of editable area
  #   toolbar  - selector of toolbar area
  constructor: (@options) ->
    @editable = $(@options.editable)
    @readonly = @options.readonly
    @selectEnd()
    @sanitize = new Editor.Sanitize(this)
    @formator = new Editor.Formator(this)
    @undoManager = new Editor.UndoManager(this)
    if @options.toolbar
      @toolbar = new Editor.Toolbar(this, @options.toolbar, @options.toolbarOptions)
      @toolbar.detectState()
    @bindShortcuts()
    @initParagraph()
    _this = this
    @editable.on "keyup mouseup", ->
      _this.storeRange()

    @editable.on
      keyup: (event) ->
        _this.keyup event

      keydown: (event) ->
        _this.keydown event

      input: (event) ->
        _this.input event

      paste: (event) ->
        _this.paste event

    @is_chrome = navigator.userAgent.indexOf("Chrome") > -1
    @is_safari = navigator.userAgent.indexOf("Safari") > -1 and not @is_chrome

    # In mac, chrome in safari trigger input event when typing pinyin,
    # so use textInput event.
    if @is_chrome or @is_safari
      # webkit don't get right range offset, so setTimout to fix

      # cache word count, detect delete action
      # Backspace
      # Delete
      @editable.on("textInput", ->
        setTimeout (->
          _this.undoManager.save()
          _this.editable.trigger "editor:change"
        ), 0
      ).on("keydown", (event) ->
        switch event.keyCode
          when 8, 46
            _this.wordCount = _this.editable.html().length
      ).on "keyup", (event) ->
        # when delete action, trigger change event
        switch event.keyCode
          # Backspace, Delete
          when 8, 46
            if _this.editable.html().length < _this.wordCount
              setTimeout (->
                _this.undoManager.save()
                _this.editable.trigger "editor:change"
              ), 0

    else
      @editable.on "input", ->
        setTimeout (->
          _this.undoManager.save()
          _this.editable.trigger "editor:change"
        ), 0 # webkit don't get right range offset, so setTimout to fix

  shortcuts:
    bold: ["ctrl+b"]
    italic: ["ctrl+i"]
    image: ["ctrl+g"]
    strikeThrough: ["ctrl+d"]
    underline: ["ctrl+u"]
    link: ["ctrl+l"]
    orderedList: ["ctrl+7"]
    unorderedList: ["ctrl+8"]
    p: ["ctrl+0"]
    h1: ["ctrl+1"]
    h2: ["ctrl+2"]
    h3: ["ctrl+3"]
    h4: ["ctrl+4"]
    code: ["ctrl+k"]
    blockquote: ["ctrl+q"]
    undo: ["ctrl+z"]
    redo: ["ctrl+y", "ctrl+shift+z"]

  bindShortcuts: ->
    _this = this
    $.each @shortcuts, (method, key) ->
      if _this.formator[method]
        Mousetrap.bind key, (event) ->
          event.preventDefault()
          unless @readonly
            _this.restoreRange() unless _this.hasRange()
            _this.formator[method]()

      else if _this[method]
        Mousetrap.bind key, (event) ->
          event.preventDefault()
          _this[method]() unless @readonly

  setReadonly: (@readonly) ->
    @editable.prop('contentEditable', !@readonly)

  paste: (event) ->
    @dirty = true
  # 事件顺序 keydown input keyup
  # keydown事件发生时，输入值并没有发生变化，所以keydown可用于阻止某些输入字符的显示
  # input事件发生时，无法获取到keyCode值，并且紧随在keydown事件之后
  # keyup事件最后发生，一次键盘敲入事件彻底完成
  input: (event) ->
    _this = this
    if _this.dirty
      _this.sanitize.run()
      _this.dirty = false

  selectContents: (contents) ->
    selection = window.getSelection()
    range = selection.getRangeAt(0)
    start = contents.first()[0]
    end = contents.last()[0]
    range.setStart start, 0
    range.setEnd end, end.childNodes.length or end.length # text node don't have childNodes
    selection.removeAllRanges() # 移除所有选中的区域
    selection.addRange range # 设置contents的区域被选中

  keyup: (event) ->
    switch event.keyCode
      # Backspace
      when 8, 46 # Delete
        @initParagraph()

  triggerInput: ->
    @editable.trigger "textInput"  if @is_chrome or @is_safari

  keydown: (event) ->
    switch event.keyCode
      when 8 # Backspace
        @backspcae event
      when 13 # Enter
        @enter event

  backspcae: (event) ->
    # Stop Backspace when empty, avoid cursor flash
    event.preventDefault()  if @editable.html() is "<p><br></p>"

  enter: (event) ->
    # If in pre code, insert \n
    if document.queryCommandValue("formatBlock") is "pre"
      event.preventDefault()
      selection = window.getSelection()
      range = selection.getRangeAt(0)
      rangeAncestor = range.commonAncestorContainer
      $pre = $(rangeAncestor).closest("pre")
      range.deleteContents()
      isLastLine = ($pre.find("code").contents().last()[0] is range.endContainer)
      isEnd = (range.endContainer.length is range.endOffset)
      node = document.createTextNode("\n")
      range.insertNode node

      # keep two \n at the end, fix webkit eat \n issues.
      $pre.find("code").append document.createTextNode("\n")  if isLastLine and isEnd
      range.setStartAfter node
      range.setEndAfter node
      selection.removeAllRanges()
      selection.addRange range
      @triggerInput()

  undo: ->
    @undoManager.undo()

  redo: ->
    @undoManager.redo()

  initParagraph: ->

    # chrome is empty and firefox is <br>
    @formator.p()  if @editable.html() is "" or @editable.html() is "<br>"
  # 直接将光标放到编辑区域的最末尾
  selectEnd: ->
    selection = document.getSelection() #用户选择的文本范围或光标的当前位置
    selection.selectAllChildren @editable[0] #将editable[0]设为选中区域
    selection.collapseToEnd() #取消当前选区，并把光标定位在原选区的最末尾处

  storeRange: ->
    selection = document.getSelection()
    range = selection.getRangeAt(0)
    @storedRange =
      startContainer: range.startContainer
      startOffset: range.startOffset
      endContainer: range.endContainer
      endOffset: range.endOffset

  restoreRange: ->
    selection = document.getSelection()
    range = document.createRange() 
    if @storedRange #如果存在存储的选中区域,设置选中区域
      range.setStart @storedRange.startContainer, @storedRange.startOffset
      range.setEnd @storedRange.endContainer, @storedRange.endOffset
      selection.removeAllRanges()
      selection.addRange range
    else
      @selectEnd()

  hasRange: ->
    selection = document.getSelection()
    selection.rangeCount and $(selection.getRangeAt(0).commonAncestorContainer).closest(@options.editable).length

  reset: ->
    @editable.html('')
    @initParagraph()
    @selectEnd()
