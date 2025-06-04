
local parser = rawget(_G, "parser")
if not parser or not parser.parse then
  error("parser module or parser.parse not defined — ensure parser.lua is loaded before gui.lua")
end
local parse = parser.parse
local simplify = rawget(_G, "simplify")
-- Compatibility hack: unpack became table.unpack in newer Lua, because reasons
unpack = unpack or table.unpack
-- ETK View System (lifted and tweaked from SuperSpire/S2.lua)
defaultFocus = nil

-- The View class: manages widgets, focus, mouse events, and general UI mayhem.
View = class()

function View:init(window)
	self.window = window
	self.widgetList = {}
	self.focusList = {}
	self.currentFocus = 0
	self.currentCursor = "default"
	self.prev_mousex = 0
	self.prev_mousey = 0
end

function View:invalidate()
	self.window:invalidate()
end

function View:setCursor(cursor)
	if cursor ~= self.currentCursor then
		self.currentCursor = cursor
		self:invalidate()
	end
end

-- Add a widget to the view, because clearly we like clutter. Also handles focus logic.
function View:add(o)
	table.insert(self.widgetList, o)
	self:repos(o)
	if o.acceptsFocus then
		table.insert(self.focusList, 1, o)
		if self.currentFocus > 0 then
			self.currentFocus = self.currentFocus + 1
		end
	end
	return o
end

-- Remove a widget from the view, and try to pretend nothing ever happened.
function View:remove(o)
	if self:getFocus() == o then
		o:releaseFocus()
	end
	local i = 1
	local f = 0
	while i <= #self.focusList do
		if self.focusList[i] == o then
			f = i
		end
		i = i + 1
	end
	if f > 0 then
		if self:getFocus() == o then
			self:tabForward()
		end
		table.remove(self.focusList, f)
		if self.currentFocus > f then
			self.currentFocus = self.currentFocus - 1
		end
	end
	f = 0
	i = 1
	while i <= #self.widgetList do
		if self.widgetList[i] == o then
			f = i
		end
		i = i + 1
	end
	if f > 0 then
		table.remove(self.widgetList, f)
	end
end

-- Reposition and resize a widget according to its constraints. Because pixel-perfect UIs are for the weak.
function View:repos(o)
	local x = o.x
	local y = o.y
	local w = o.w
	local h = o.h
	if o.hConstraint == "right" then
		x = scrWidth - o.w - o.dx1
	elseif o.hConstraint == "center" then
		x = (scrWidth - o.w + o.dx1) / 2
	elseif o.hConstraint == "justify" then
		w = scrWidth - o.x - o.dx1
	end
	if o.vConstraint == "bottom" then
		y = scrHeight - o.h - o.dy1
	elseif o.vConstraint == "middle" then
		y = (scrHeight - o.h + o.dy1) / 2
	elseif o.vConstraint == "justify" then
		h = scrHeight - o.y - o.dy1
	end
	o:repos(x, y)
	o:resize(w, h)
end

-- Resize all widgets in the view. Hope they like their new size.
function View:resize()
	for _, o in ipairs(self.widgetList) do
		self:repos(o)
	end
end

-- Hide a widget. Out of sight, out of mind (and out of focus).
function View:hide(o)
	if o.visible then
		o.visible = false
		self:releaseFocus(o)
		if o:contains(self.prev_mousex, self.prev_mousey) then
			o:onMouseLeave(o.x - 1, o.y - 1)
		end
		self:invalidate()
	end
end

-- Show a widget. If it was invisible, now it can bask in the user's gaze.
function View:show(o)
	if not o.visible then
		o.visible = true
		if o:contains(self.prev_mousex, self.prev_mousey) then
			o:onMouseEnter(self.prev_mousex, self.prev_mousey)
		end
		self:invalidate()
	end
end

-- Return the currently focused widget, or nil if nothing bothers to have focus.
function View:getFocus()
	if self.currentFocus == 0 then
		return nil
	end
	return self.focusList[self.currentFocus]
end

-- Give focus to a widget, and make everyone else jealous.
function View:setFocus(obj)
	if self.currentFocus ~= 0 then
		if self.focusList[self.currentFocus] == obj then
			return
		end
		self.focusList[self.currentFocus]:releaseFocus()
	end
	self.currentFocus = 0
	for i = 1, #self.focusList do
		if self.focusList[i] == obj then
			self.currentFocus = i
			obj:setFocus()
			self:invalidate()
			break
		end
	end
end

-- Take focus away from a widget. It probably didn't deserve it anyway.
function View:releaseFocus(obj)
	if self.currentFocus ~= 0 then
		if self.focusList[self.currentFocus] == obj then
			self.currentFocus = 0
			obj:releaseFocus()
			self:invalidate()
		end
	end
end

-- Send a string to the focused widget, or desperately try to find anyone who will take it.
function View:sendStringToFocus(str)
	local o = self:getFocus()
	if not o then
		o = defaultFocus
		self:setFocus(o)
	end
	if o then
		if o.visible then
			if o:addString(str) then
				self:invalidate()
			else
				o = nil
			end
		end
	end

	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible then
				if o:addString(str) then
					self:setFocus(o)
					self:invalidate()
					break
				end
			end
		end
	end
end

-- Handle backspace for the focused widget, or for anyone who claims to accept it.
function View:backSpaceHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsBackSpace then
			o:backSpaceHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsBackSpace then
				o:backSpaceHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Move focus to the next widget, looping around. Because tab order is a suggestion, not a rule.
function View:tabForward()
	local nextFocus = self.currentFocus + 1
	if nextFocus > #self.focusList then
		nextFocus = 1
	end
	self:setFocus(self.focusList[nextFocus])
	if self:getFocus() then
		if not self:getFocus().visible then
			self:tabForward()
		end
	end
	self:invalidate()
end

-- Move focus to the previous widget, looping around. For the rebels who like shift+tab.
function View:tabBackward()
	local nextFocus = self.currentFocus - 1
	if nextFocus < 1 then
		nextFocus = #self.focusList
	end
	self:setFocus(self.focusList[nextFocus])
	if not self:getFocus().visible then
		self:tabBackward()
	end
	self:invalidate()
end

-- Handle mouse down events, capturing the widget that gets clicked (and focus).
function View:onMouseDown(x, y)
	for _, o in ipairs(self.widgetList) do
		if o.visible and o.acceptsFocus and o:contains(x, y) then
			self.mouseCaptured = o
			o:onMouseDown(o, window, x - o.x, y - o.y)
			self:setFocus(o)
			self:invalidate()
			return
		end
	end
	if self:getFocus() then
		self:setFocus(nil)
		self:invalidate()
	end
end

-- Handle mouse move events, triggering enter/leave events for widgets. Because hover states are important.
function View:onMouseMove(x, y)
	local prev_mousex = self.prev_mousex
	local prev_mousey = self.prev_mousey
	for _, o in ipairs(self.widgetList) do
		local xyin = o:contains(x, y)
		local prev_xyin = o:contains(prev_mousex, prev_mousey)
		if xyin and not prev_xyin and o.visible then
			o:onMouseEnter(x, y)
			self:invalidate()
		elseif prev_xyin and (not xyin or not o.visible) then
			o:onMouseLeave(x, y)
			self:invalidate()
		end
	end
	self.prev_mousex = x
	self.prev_mousey = y
end

-- Handle mouse up events, releasing the widget that was so rudely pressed.
function View:onMouseUp(x, y)
	local mc = self.mouseCaptured
	if mc then
		self.mouseCaptured = nil
		if mc:contains(x, y) then
			mc:onMouseUp(x - mc.x, y - mc.y)
		end
	end
end

-- Handle "enter" key for the focused widget, or anyone who cares.
function View:enterHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsEnter then
			o:enterHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsEnter then
				o:enterHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Handle left arrow key for the focused widget, or anyone who wants to move left in life.
function View:arrowLeftHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowLeft then
			o:arrowLeftHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowLeft then
				o:arrowLeftHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Handle right arrow key for the focused widget, or anyone who wants to move right in life.
function View:arrowRightHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowRight then
			o:arrowRightHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowRight then
				o:arrowRightHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Handle up arrow key for the focused widget. Because up is the new down.
function View:arrowUpHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowUp then
			o:arrowUpHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowUp then
				o:arrowUpHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Handle down arrow key for the focused widget. Because down is the new up.
function View:arrowDownHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowDown then
			o:arrowDownHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowDown then
				o:arrowDownHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

-- Paint all widgets to the screen, highlight the focused one, and set the cursor.
function View:paint(gc)
	local fo = self:getFocus()
	for _, o in ipairs(self.widgetList) do
		if o.visible then
			o:paint(gc, fo == o)
			if fo == o then
				gc:setColorRGB(100, 150, 255)
				gc:drawRect(o.x - 1, o.y - 1, o.w + 1, o.h + 1)
				gc:setPen("thin", "smooth")
				gc:setColorRGB(0, 0, 0)
			end
		end
	end
	cursor.set(self.currentCursor)
end

theView = nil

-- Widget base class. All widgets inherit from this, like it or not.
Widget = class()

function Widget:setHConstraints(hConstraint, dx1)
	self.hConstraint = hConstraint
	self.dx1 = dx1
end

function Widget:setVConstraints(vConstraint, dy1)
	self.vConstraint = vConstraint
	self.dy1 = dy1
end

function Widget:init(view, x, y, w, h)
	self.xOrig = x
	self.yOrig = y
	self.view = view
	self.x = x
	self.y = y
	self.w = w
	self.h = h
	self.acceptsFocus = false
	self.visible = true
	self.acceptsEnter = false
	self.acceptsEscape = false
	self.acceptsTab = false
	self.acceptsDelete = false
	self.acceptsBackSpace = false
	self.acceptsReturn = false
	self.acceptsArrowUp = false
	self.acceptsArrowDown = false
	self.acceptsArrowLeft = false
	self.acceptsArrowRight = false
	self.hConstraint = "left"
	self.vConstraint = "top"
end

function Widget:repos(x, y)
	self.x = x
	self.y = y
end

function Widget:resize(w, h)
	self.w = w
	self.h = h
end

function Widget:setFocus() end
function Widget:releaseFocus() end

function Widget:contains(x, y)
	return x >= self.x and x <= self.x + self.w
			and y >= self.y and y <= self.y + self.h
end

function Widget:onMouseEnter(x, y) end
function Widget:onMouseLeave(x, y) end
function Widget:paint(gc, focused) end
function Widget:enterHandler() end
function Widget:escapeHandler() end
function Widget:tabHandler() end
function Widget:deleteHandler() end
function Widget:backSpaceHandler() end
function Widget:returnHandler() end
function Widget:arrowUpHandler() end
function Widget:arrowDownHandler() end
function Widget:arrowLeftHandler() end
function Widget:arrowRightHandler() end
function Widget:onMouseDown(x, y) end
function Widget:onMouseUp(x, y) end

-- Button widget, for people who like clicking things.
Button = class(Widget)

function Button:init(view, x, y, w, h, default, command, shortcut)
	Widget.init(self, view, x, y, w, h)
	self.acceptsFocus = true
	self.command = command or function() end
	self.default = default
	self.shortcut = shortcut
	self.clicked = false
	self.highlighted = false
	self.acceptsEnter = true
end

function Button:enterHandler()
	if self.acceptsEnter then
		self:command()
	end
end

function Button:escapeHandler()
	if self.acceptsEscape then
		self:command()
	end
end

function Button:tabHandler()
	if self.acceptsTab then
		self:command()
	end
end

function Button:deleteHandler()
	if self.acceptsDelete then
		self:command()
	end
end

function Button:backSpaceHandler()
	if self.acceptsBackSpace then
		self:command()
	end
end

function Button:returnHandler()
	if self.acceptsReturn then
		self:command()
	end
end

function Button:arrowUpHandler()
	if self.acceptsArrowUp then
		self:command()
	end
end

function Button:arrowDownHandler()
	if self.acceptsArrowDown then
		self:command()
	end
end

function Button:arrowLeftHandler()
	if self.acceptsArrowLeft then
		self:command()
	end
end

function Button:arrowRightHandler()
	if self.acceptsArrowRight then
		self:command()
	end
end

function Button:onMouseDown(x, y)
	self.clicked = true
	self.highlighted = true
end

function Button:onMouseEnter(x, y)
	theView:setCursor("hand pointer")
	if self.clicked and not self.highlighted then
		self.highlighted = true
	end
end

function Button:onMouseLeave(x, y)
	theView:setCursor("default")
	if self.clicked and self.highlighted then
		self.highlighted = false
	end
end

function Button:cancelClick()
	if self.clicked then
		self.highlighted = false
		self.clicked = false
	end
end

function Button:onMouseUp(x, y)
	self:cancelClick()
	self:command()
end

function Button:addString(str)
	if str == " " or str == self.shortcut then
		self:command()
		return true
	end
	return false
end

-- Image label widget. Displays an image, does nothing else. The laziest widget.
ImgLabel = class(Widget)

function ImgLabel:init(view, x, y, img)
	self.img = image.new(img)
	self.w = image.width(self.img)
	self.h = image.height(self.img)
	Widget.init(self, view, x, y, self.w, self.h)
end

function ImgLabel:paint(gc, focused)
	gc:drawImage(self.img, self.x, self.y)
end

-- Image button widget. Like a button, but with more pixels.
ImgButton = class(Button)

function ImgButton:init(view, x, y, img, command, shortcut)
	self.img = image.new(img)
	self.w = image.width(self.img)
	self.h = image.height(self.img)
	Button.init(self, view, x, y, self.w, self.h, false, command, shortcut)
end

function ImgButton:paint(gc, focused)
	gc:drawImage(self.img, self.x, self.y)
end

-- Text button widget. For those who prefer words to icons.
TextButton = class(Button)

function TextButton:init(view, x, y, text, command, shortcut)
	self.textid = text
	self.text = getLocaleText(text)
	self:resize(0, 0)
	Button.init(self, view, x, y, self.w, self.h, false, command, shortcut)
end

function TextButton:resize(w, h)
	self.text = getLocaleText(self.textid)
	self.w = getStringWidth(self.text) + 5
	self.h = getStringHeight(self.text) + 5
end

function TextButton:paint(gc, focused)
	gc:setColorRGB(223, 223, 223)
	gc:drawRect(self.x + 1, self.y + 1, self.w - 2, self.h - 2)
	gc:setColorRGB(191, 191, 191)
	gc:fillRect(self.x + 1, self.y + 1, self.w - 3, self.h - 3)
	gc:setColorRGB(223, 223, 223)
	gc:drawString(self.text, self.x + 3, self.y + 3, "top")
	gc:setColorRGB(0, 0, 0)
	gc:drawString(self.text, self.x + 2, self.y + 2, "top")
	gc:drawRect(self.x, self.y, self.w - 2, self.h - 2)
end

-- Vertical scrollbar widget. Because scrolling through history is a thing.
VScrollBar = class(Widget)

function VScrollBar:init(view, x, y, w, h)
	self.pos = 10
	self.siz = 10
	Widget.init(self, view, x, y, w, h)
end

function VScrollBar:paint(gc, focused)
	gc:setColorRGB(0, 0, 0)
	gc:drawRect(self.x, self.y, self.w, self.h)
	gc:fillRect(self.x + 2, self.y + self.h - (self.h - 4) * (self.pos + self.siz) / 100 - 2, self.w - 3, math.max(1, (self.h - 4) * self.siz / 100 + 1))
end

-- Text label widget. It just sits there and looks pretty.
TextLabel = class(Widget)

function TextLabel:init(view, x, y, text)
	self:setText(text)
	Widget.init(self, view, x, y, self.w, self.h)
end

function TextLabel:resize(w, h)
	self.text = getLocaleText(self.textid)
	self.w = getStringWidth(self.text)
	self.h = getStringHeight(self.text)
end

function TextLabel:setText(text)
	self.textid = text
	self.text = getLocaleText(text)
	self:resize(0, 0)
end

function TextLabel:getText()
	return self.text
end

function TextLabel:paint(gc, focused)
	gc:setColorRGB(0, 0, 0)
	gc:drawString(self.text, self.x, self.y, "top")
end

-- Rich text editor widget. Handles text entry, but don't expect Microsoft Word.
RichTextEditor = class(Widget)

function RichTextEditor:init(view, x, y, w, h, text)
	self.editor = D2Editor.newRichText()
	self.readOnly = false
	self:repos(x, y)
	self.editor:setFontSize(fsize)
	self.editor:setFocus(false)
	self.text = text
	self:resize(w, h)
	Widget.init(self, view, x, y, self.w, self.h, true)
	self.acceptsFocus = true
	self.editor:setExpression(text)
	self.editor:setBorder(1)
end

function RichTextEditor:onMouseEnter(x, y)
	theView:setCursor("text")
end

function RichTextEditor:onMouseLeave(x, y)
	theView:setCursor("default")
end

function RichTextEditor:repos(x, y)
	if not self.editor then return end
	self.editor:setBorderColor((showEditorsBorders and 0) or 0xffffff )
	self.editor:move(x, y)
	Widget.repos(self, x, y)
end

function RichTextEditor:resize(w, h)
	if not self.editor then return end
	self.editor:resize(w, h)
	Widget.resize(self, w, h)
end

function RichTextEditor:setFocus()
	self.editor:setFocus(true)
end

function RichTextEditor:releaseFocus()
	self.editor:setFocus(false)
end

function RichTextEditor:addString(str)
	local currentText = self.editor:getText() or ""
	self.editor:setText(currentText .. str)
	return true
end

function RichTextEditor:paint(gc, focused) end

-- MathEditor: a rich text editor with math-specific quirks and a love for Unicode.
MathEditor = class(RichTextEditor)

-- Returns the number of Unicode codepoints in a string.
-- Because Lua strings are byte-based and Unicode is hard.
function ulen(str)
	if not str then return 0 end
	local n = string.len(str)
	local i = 1
	local j = 1
	local c
	while (j <= n) do
		c = string.len(string.usub(str, i, i))
		j = j + c
		i = i + 1
	end
	return i - 1
end

-- Initialize a MathEditor, set up filters for key events, and generally make life complicated.
function MathEditor:init(view, x, y, w, h, text)
	RichTextEditor.init(self, view, x, y, w, h, text)
	self.editor:setBorder(1)
	self.acceptsEnter = true
	self.acceptsBackSpace = true
	self.result = false
	self.editor:registerFilter({
		arrowLeft = function()
			_, curpos = self.editor:getExpressionSelection()
			if curpos < 7 then
				on.arrowLeft()
				return true
			end
			return false
		end,
		arrowRight = function()
			currentText, curpos = self.editor:getExpressionSelection()
			if curpos > ulen(currentText) - 2 then
				on.arrowRight()
				return true
			end
			return false
		end,
		tabKey = function()
			theView:tabForward()
			return true
		end,
		mouseDown = function(x, y)
			theView:onMouseDown(x, y)
			return false
		end,
		backspaceKey = function()
			if (self == fctEditor) then
				self:fixCursor()
				_, curpos = self.editor:getExpressionSelection()
				if curpos <= 6 then return true end
				return false
			else
				self:backSpaceHandler()
				return true
			end
		end,
		deleteKey = function()
			if (self == fctEditor) then
				self:fixCursor()
				currentText, curpos = self.editor:getExpressionSelection()
				if curpos >= ulen(currentText) - 1 then return true end
				return false
			else
				self:backSpaceHandler()
				return true
			end
		end,
		enterKey = function()
			self:enterHandler()
			return true
		end,
		returnKey = function()
			theView:enterHandler()
			return true
		end,
		escapeKey = function()
			on.escapeKey()
			return true
		end,
		charIn = function(c)
			if (self == fctEditor) then
				self:fixCursor()
				return false
			else
				return self.readOnly
			end
		end
	})
end

-- Ensures the editor has a math box at all times.
function MathEditor:fixContent()
	local currentText = self.editor:getExpressionSelection()
	if currentText == "" or currentText == nil then
		self.editor:createMathBox()
	end
end

-- Make sure the cursor stays inside the editable region of the Unicode string.
-- D2Editor likes to insert special tokens at the start, so we have to skip the first 6 codepoints.
-- If the cursor escapes the allowed range, forcibly drag it back, because users can't be trusted.
function MathEditor:fixCursor()
	local currentText, curpos, selstart = self.editor:getExpressionSelection()
	local l = ulen(currentText)
	if curpos < 6 or selstart < 6 or curpos > l - 1 or selstart > l - 1 then
		if curpos < 6 then curpos = 6 end
		if selstart < 6 then selstart = 6 end
		if curpos > l - 1 then curpos = l - 1 end
		if selstart > l - 1 then selstart = l - 1 end
		self.editor:setExpression(currentText, curpos, selstart)
	end
end

-- Extract the user-entered expression from the D2Editor string, skipping any special formatting.
function MathEditor:getExpression()
	if not self.editor then return "" end
	local rawexpr = self.editor:getExpression()
	local expr = ""
	local n = string.len(rawexpr)
	local b = 0
	local bs = 0
	local bi = 0
	local status = 0
	local i = 1
	while i <= n do
		local c = string.sub(rawexpr, i, i)
		if c == "{" then
			b = b + 1
		elseif c == "}" then
			b = b - 1
		end
		if status == 0 then
			if string.sub(rawexpr, i, i + 5) == "\\0el {" then
				bs = i + 6
				i = i + 5
				status = 1
				bi = b
				b = b + 1
			end
		else
			if b == bi then
				status = 0
				expr = expr .. string.sub(rawexpr, bs, i - 1)
			end
		end
		i = i + 1
	end
	return expr
end

-- Set focus to the math editor, so it can feel important.
function MathEditor:setFocus()
	if not self.editor then return end
	self.editor:setFocus(true)
end

-- Remove focus from the math editor, so it can sulk in the corner.
function MathEditor:releaseFocus()
	if not self.editor then return end
	self.editor:setFocus(false)
end

-- Inserts text at the cursor. Assumes user knows what they’re doing. (They probably don’t.)
function MathEditor:addString(str)
	if not self.editor then return false end
	self:fixCursor()
	-- Unicode string slicing: because normal string.sub just isn't enough.
	local currentText, curpos, selstart = self.editor:getExpressionSelection()
	local newText = string.usub(currentText, 1, math.min(curpos, selstart)) .. str .. string.usub(currentText, math.max(curpos, selstart) + 1, ulen(currentText))
	self.editor:setExpression(newText, math.min(curpos, selstart) + ulen(str))
	return true
end

-- Handle backspace. (No-op for now, because history deletion is scary.)
function MathEditor:backSpaceHandler()
    -- No-op or custom deletion logic (history removal not implemented)
end

-- Handle enter key. Just delegates to the real handler.
function MathEditor:enterHandler()
    -- Call the custom on.enterKey handler instead of missing global
    on.enterKey()
end

-- Draws horizontal lines under the editor, if we're feeling fancy.
function MathEditor:paint(gc)
	if showHLines and not self.result then
		gc:setColorRGB(100, 100, 100)
		local ycoord = self.y - (showEditorsBorders and 0 or 2)
		gc:drawLine(1, ycoord, platform.window:width() - sbv.w - 2, ycoord)
		gc:setColorRGB(0, 0, 0)
	end
end

function on.arrowUp()
  if theView then
    if theView:getFocus() == fctEditor then
      on.tabKey()
    else
      on.tabKey()
      if theView:getFocus() ~= fctEditor then on.tabKey() end
    end
    reposView()
  end
end

function on.arrowDown()
  if theView then
    on.backtabKey()
    if theView:getFocus() ~= fctEditor then on.backtabKey() end
    reposView()
  end
end

function on.arrowLeft()
  if theView then
    on.tabKey()
    reposView()
  end
end

function on.arrowRight()
  if theView then
    on.backtabKey()
    reposView()
  end
end

function on.charIn(ch)
  if theView then theView:sendStringToFocus(ch) end
end

function on.tabKey()
  if theView then theView:tabForward(); reposView() end
end

function on.backtabKey()
  if theView then theView:tabBackward(); reposView() end
end

-- This one’s the brains of the operation. Parses input, handles edge cases,
-- pretends to understand integration, and maybe even returns something useful.
function on.enterKey()
  if not fctEditor or not fctEditor.getExpression then return end

  local input = fctEditor:getExpression()
  -- Fix TI-style derivative notation like ((d)/(dx(x^2))) to diff(x^2, x)
  input = input:gsub("%(%(d%)%)%/%(d([a-zA-Z])%((.-)%)%)%)", function(var, inner)
    _G.__diff_var = var
    return inner
  end)
  if not input or input == "" then return end

  -- Remove all whitespace from input
  input = input:gsub("%s+", "")

  local result = ""
  _G.luaCASerror = false
  local success, err = pcall(function()
    if input:sub(1,4) == "d/dx" or input:sub(1,4) == "d/dy" then
      local expr = input:match("d/d[xy]%((.+)%)")
      result = expr and derivative(expr, _G.__diff_var) or "Invalid format"
      if result == "Invalid format" then _G.luaCASerror = true end
    elseif input:sub(1,5) == "∂/∂x(" and input:sub(-1) == ")" then
      local expr = input:match("∂/∂x%((.+)%)")
      result = expr and derivative(expr, _G.__diff_var) or "Invalid format"
      if result == "Invalid format" then _G.luaCASerror = true end
    elseif input:match("^∂/∂[yz]%(.+%)$") then
      result = derivative(input, _G.__diff_var)
    elseif input:sub(1,3) == "∫(" and input:sub(-2) == ")x" then
      result = integrate(parse(input:sub(4, -3)))
    elseif input:sub(1,4) == "int(" and input:sub(-1) == ")" then
      local expr = input:match("int%((.+)%)")
      result = expr and integrate(parse(expr)) or "Invalid format"
      if result == "Invalid format" then _G.luaCASerror = true end
    elseif input:sub(1,6) == "solve(" and input:sub(-1) == ")" then
      local eqn = input:match("solve%((.+)%)")
      if eqn and not eqn:find("=") then
        eqn = eqn .. "=0"
      end
      result = eqn and solve(parse(eqn)) or "Invalid solve format"
      if result == "Invalid solve format" then _G.luaCASerror = true end
    elseif input:sub(1,4) == "let" then
      result = define(input)
    elseif input:sub(1,7) == "expand(" and input:sub(-1) == ")" then
        local inner = input:match("expand%((.+)%)")
        result = inner and expand(parse(inner)) or "Invalid expand format"
        if result == "Invalid expand format" then _G.luaCASerror = true end
    elseif input:sub(1,5) == "subs(" and input:sub(-1) == ")" then
        local inner, var, val = input:match("subs%(([^,]+),([^,]+),([^%)]+)%)")
        result = (inner and var and val) and subs(parse(inner), var, val) or "Invalid subs format"
        if result == "Invalid subs format" then _G.luaCASerror = true end
    elseif input:sub(1,7) == "factor(" and input:sub(-1) == ")" then
        local inner = input:match("factor%((.+)%)")
        result = inner and factor(parse(inner)) or "Invalid factor format"
        if result == "Invalid factor format" then _G.luaCASerror = true end
    elseif input:sub(1,4) == "gcd(" and input:sub(-1) == ")" then
        local a, b = input:match("gcd%(([^,]+),([^%)]+)%)")
        result = (a and b) and gcd(parse(a), parse(b)) or "Invalid gcd format"
        if result == "Invalid gcd format" then _G.luaCASerror = true end
    elseif input:sub(1,4) == "lcm(" and input:sub(-1) == ")" then
        local a, b = input:match("lcm%(([^,]+),([^%)]+)%)")
        result = (a and b) and lcm(parse(a), parse(b)) or "Invalid lcm format"
        if result == "Invalid lcm format" then _G.luaCASerror = true end
    elseif input:sub(1,7) == "trigid(" and input:sub(-1) == ")" then
        local inner = input:match("trigid%((.+)%)")
        result = inner and trigid(parse(inner)) or "Invalid trigid format"
        if result == "Invalid trigid format" then _G.luaCASerror = true end
    elseif input:match("%w+%(.+%)") then
      result = simplify.simplify(parse(input))
    elseif input:sub(1,9) == "simplify(" and input:sub(-1) == ")" then
      local inner = input:match("simplify%((.+)%)")
      result = inner and simplify.simplify(parse(inner)) or "Invalid simplify format"
      if result == "Invalid simplify format" then _G.luaCASerror = true end
    -- Fallback parser for diff(...) and integrate(...)
    elseif input:match("^diff%(([^,]+),([^,%)]+)%)$") then
      local a, b = input:match("^diff%(([^,]+),([^,%)]+)%)$")
      result = (a and b) and derivative(parse(a), b) or "Invalid diff() format"
      if result == "Invalid diff() format" then _G.luaCASerror = true end
    elseif _G.__diff_var then
      result = derivative(input, _G.__diff_var)
      _G.__diff_var = nil
    elseif input:match("^integrate%(([^,]+),([^,%)]+)%)$") then
      local a, b = input:match("^integrate%(([^,]+),([^,%)]+)%)$")
      result = (a and b) and integrate(parse(a), b) or "Invalid integrate() format"
      if result == "Invalid integrate() format" then _G.luaCASerror = true end
    else
      result = simplify.simplify(parse(input))
    end
    if result == "" or not result then
      result = "No result. Internal CAS fallback used."
    end
  end)
  if not success then
    result = "Error: " .. tostring(err)
    _G.luaCASerror = true
  end

  -- Add to history display
  local colorHint = (_G.luaCASerror and "error") or "normal"
  addME(input, result, colorHint)

  -- Clear the input editor and ready for next input
  if fctEditor and fctEditor.editor then
    fctEditor.editor:setText("")
    fctEditor:fixContent()
  end

  -- Redraw UI
  if platform and platform.window and platform.window.invalidate then
    platform.window:invalidate()
  end

  -- Optionally save last result globally if needed
  if type(result) == "table" then
    if _G.ast and _G.ast.tostring then
      result = _G.ast.tostring(result)
    else
      result = "(unrenderable result)"
    end
  end
  res = result
end

function on.returnKey()
  on.enterKey()
end

function on.mouseMove(x, y)
  if theView then theView:onMouseMove(x, y) end
end

function on.mouseDown(x, y)
  if theView then theView:onMouseDown(x, y) end
end

function on.mouseUp(x, y)
  if theView then theView:onMouseUp(x, y) end
end

function initFontGC(gc)
	gc:setFont(font, style, fsize)
end

function getStringHeightGC(text, gc)
	initFontGC(gc)
	return gc:getStringHeight(text)
end

function getStringHeight(text)
	return platform.withGC(getStringHeightGC, text)
end

function getStringWidthGC(text, gc)
	initFontGC(gc)
	return gc:getStringWidth(text)
end

function getStringWidth(text)
	return platform.withGC(getStringWidthGC, text)
end


----------------------------------------------------------------------
--                           History Layout                           --
----------------------------------------------------------------------

-- Find the “partner” editor for a history entry
function getParME(editor)
    for i = 1, #histME2 do
        if histME2[i].editor == editor then
            return histME1[i]
        end
    end
    return nil
end

-- Map a D2Editor instance back to its MathEditor wrapper
function getME(editor)
    if fctEditor and fctEditor.editor == editor then
        return fctEditor
    else
        for i = 1, #histME1 do
            if histME1[i].editor == editor then
                return histME1[i]
            end
        end
        for i = 1, #histME2 do
            if histME2[i].editor == editor then
                return histME2[i]
            end
        end
    end
    return nil
end

-- Get the “index” of a given MathEditor in the history stack
function getMEindex(me)
    if fctEditor and fctEditor.editor == me then
        return 0
    else
        local ti = 0
        for i = #histME1, 1, -1 do
            if histME1[i] == me then
                return ti
            end
            ti = ti + 1
        end
        ti = 0
        for i = #histME2, 1, -1 do
            if histME2[i] == me then
                return ti
            end
            ti = ti + 1
        end
    end
    return 0
end

-- Global offset for history scrolling
ioffset = 0

function reposView()
    local focusedME = theView:getFocus()
    if not focusedME or focusedME == fctEditor then return end

    local index = getMEindex(focusedME)
    local maxIterations = 10 -- prevent infinite loops
    for _ = 1, maxIterations do
        local y = focusedME.y
        local h = focusedME.h
        local y0 = fctEditor.y

        if y < 0 and ioffset < index then
            ioffset = ioffset + 1
            reposME()
        elseif y + h > y0 and ioffset > index then
            ioffset = ioffset - 1
            reposME()
        else
            break
        end
    end
end

-- When a history editor resizes, lay out paired entries side-by-side
function resizeMEpar(editor, w, h)
    local pare = getParME(editor)
    if pare then
        resizeMElim(editor, w, h, pare.w + (pare.dx1 or 0) * 2)
    else
        resizeME(editor, w, h)
    end
end

-- Generic resize for any MathEditor
function resizeME(editor, w, h)
    if not editor then return end
    resizeMElim(editor, w, h, scrWidth / 2)
end

-- Internal workhorse for resizing (limits width, then calls reposME)
function resizeMElim(editor, w, h, lim)
    if not editor then return end
    local met = getME(editor)
    if met then
        met.needw = w
        met.needh = h
        w = math.max(w, 0)
        w = math.min(w, scrWidth - (met.dx1 or 0) * 2)
        if met ~= fctEditor then
            w = math.min(w, (scrWidth - lim) - 2 * (met.dx1 or 0) + 1)
        end
        h = math.max(h, strFullHeight + 8)
        met:resize(w, h)
        reposME()
        theView:invalidate()
    end
    return editor
end

-- “Scroll” and reflow all history MathEditors on screen
function reposME()
    local totalh, beforeh, visih = 0, 0, 0

    -- First, position the input editor at the bottom
    fctEditor.y = scrHeight - fctEditor.h
    theView:repos(fctEditor)

    -- Update scrollbar to fill from input up
    sbv:setVConstraints("justify", scrHeight - fctEditor.y + border)
    theView:repos(sbv)

    local y = fctEditor.y
    local i0 = math.max(#histME1, #histME2)

    for i = i0, 1, -1 do
        local h1, h2 = 0, 0
        if i <= #histME1 then h1 = math.max(h1, histME1[i].h) end
        if i <= #histME2 then h2 = math.max(h2, histME2[i].h) end
        local h = math.max(h1, h2)

        local ry
        if (i0 - i) >= ioffset then
            if y >= 0 then
                if y >= h + border then
                    visih = visih + h + border
                else
                    visih = visih + y
                end
            end
            y = y - h - border
            ry = y
            totalh = totalh + h + border
        else
            ry = scrHeight
            beforeh = beforeh + h + border
            totalh = totalh + h + border
        end

        -- Place the “expression” editor on the left
        if i <= #histME1 then
            histME1[i].y = ry
            theView:repos(histME1[i])
        end
        -- Place its paired “result” editor on the right, vertically aligned
        if i <= #histME2 then
            histME2[i].y = ry + math.max(0, h1 - h2)
            theView:repos(histME2[i])
        end
    end

    if totalh == 0 then
        sbv.pos = 0
        sbv.siz = 100
    else
        sbv.pos = beforeh * 100 / totalh
        sbv.siz = visih * 100 / totalh
    end

    theView:invalidate()
end

function initGUI()
    showEditorsBorders = false
    showHLines = true
    -- local riscas = math.evalStr("iscas()")
    -- if (riscas == "true") then iscas = true end
    local id = math.eval("sslib\\getid()")
    if id then caslib = id end
    scrWidth = platform.window:width()
    scrHeight = platform.window:height()
    if scrWidth > 0 and scrHeight > 0 then
        theView = View(platform.window)

        -- Vertical scroll bar for history
        sbv = VScrollBar(theView, 0, -1, 5, scrHeight + 1)
        sbv:setHConstraints("right", 0)
        theView:add(sbv)

        -- Input editor at bottom (MathEditor)
        fctEditor = MathEditor(theView, 2, border, scrWidth - 4 - sbv.w, 30, "")
        fctEditor:setHConstraints("justify", 1)
        fctEditor:setVConstraints("bottom", 1)
        fctEditor.editor:setSizeChangeListener(function(editor, w, h)
            return resizeME(editor, w, h)
        end)
        theView:add(fctEditor)
        fctEditor.result = res
        fctEditor.editor:setText("")
        fctEditor:fixContent()

        -- First-focus is input editor
        theView:setFocus(fctEditor)
        inited = true
    end

    toolpalette.enableCopy(true)
    toolpalette.enablePaste(true)
end

function resizeGC(gc)
	scrWidth = platform.window:width()
	scrHeight = platform.window:height()
	if not inited then
		initGUI()
	end
	if inited then
		initFontGC(gc)
		strFullHeight = gc:getStringHeight("H")
		strHeight = strFullHeight - 3
		theView:resize()
		reposME()
		theView:invalidate()
	end
end

function on.resize()
	platform.withGC(resizeGC)
end

forcefocus = true

function on.activate()
	forcefocus = true
end

dispinfos = true

-- The main UI rendering phase: draws status, output, and all widgets.
-- If you’re looking for where the magic (or horror) happens, it’s here.
function on.paint(gc)
	if not inited then
		initGUI()
		initFontGC(gc)
		strFullHeight = gc:getStringHeight("H")
		strHeight = strFullHeight - 3
	end
	if inited then
		-- Removed display of "Last: ..." result at the top
		local obj = theView:getFocus()
		initFontGC(gc)
		if not obj then theView:setFocus(fctEditor) end
		if (forcefocus) then
			if obj == fctEditor then
				fctEditor.editor:setFocus(true)
				if fctEditor.editor:hasFocus() then forcefocus = false end
			else
				forcefocus = false
			end
		end
		if dispinfos then
			-- Draw status box: green if OK, red if error, always visible top left
			local engineStatus = "LuaCAS Engine: Enabled"
			local statusColor = {0, 127, 0} -- green
			if _G.luaCASerror then
				engineStatus = "LuaCAS Engine: NONE"
				statusColor = {200, 0, 0} -- red
			end
			local boxX, boxY = 8, 8
			local boxPaddingX, boxPaddingY = 10, 3
			local fontToUse = "sansserif"
			local fontStyle = "b"
			local fontSize = 11
			gc:setFont(fontToUse, fontStyle, fontSize)
			local textW = gc:getStringWidth(engineStatus)
			local textH = gc:getStringHeight(engineStatus)
			gc:setColorRGB(statusColor[1], statusColor[2], statusColor[3])
			gc:fillRect(boxX, boxY, textW + boxPaddingX * 2, textH + boxPaddingY * 2)
			gc:setColorRGB(255,255,255)
			gc:drawString(engineStatus, boxX + boxPaddingX, boxY + boxPaddingY, "top")
			-- restore font for rest of UI
			gc:setFont(font, style, fsize)
		end
		-- Output string fallback for "main" view
		if true then -- "main" view block
			local output = fctEditor and fctEditor.result
			-- local outputStr = output or ""
			local outputStr = (output and output ~= "") and output or "(no output)"
			-- If you want to draw the output somewhere, do so here.
			gc:setColorRGB(0, 127, 0)
			gc:drawString(outputStr, 10, scrHeight - 25, "top")
		end
		theView:paint(gc)
	end
end

font = "sansserif"
style = "r"
fsize = 9

scrWidth = 0
scrHeight = 0
inited = false
iscas = false
caslib = "NONE"
delim = " ≟ "
border = 3

strHeight = 0
strFullHeight = 0



-- Initialize empty history tables
histME1 = {}
histME2 = {}


-- Reminder: this is the thing that dumps both the input and result into history.
function addME(expr, res, colorHint)
	mee = MathEditor(theView, border, border, 50, 30, "")
	mee.readOnly = true
	table.insert(histME1, mee)
	mee:setHConstraints("left", border)
	mee.editor:setSizeChangeListener(function(editor, w, h)
		return resizeME(editor, w + 3, h)
	end)
	-- Set border color based on colorHint
	if colorHint == "error" then
		mee.editor:setBorderColor(0xFF0000) -- red
	else
		mee.editor:setBorderColor(0x000000)
	end
	mee.editor:setExpression("\\0el {" .. expr .. "}", 0)
	mee:fixCursor()
	mee.editor:setReadOnly(true)
	theView:add(mee)

	mer = MathEditor(theView, border, border, 50, 30, "")
    mer.result = true
    mer.readOnly = true
	table.insert(histME2, mer)
	mer:setHConstraints("right", scrWidth - sbv.x + border)
	mer.editor:setSizeChangeListener(function(editor, w, h)
				return resizeMEpar(editor, w + border, h)
	end)
	if colorHint == "error" then
		mer.editor:setBorderColor(0xFF0000) -- red
	else
		mer.editor:setBorderColor(0x000000)
	end
    local displayRes = ""
    if type(res) == "table" then
      if _G.simplify and _G.simplify.pretty_print then
        displayRes = _G.simplify.pretty_print(res)
      elseif _G.ast and _G.ast.tostring then
        displayRes = _G.ast.tostring(res)
      else
        displayRes = tostring(res)
      end
    else
      displayRes = tostring(res)
    end
    mer.editor:setExpression("\\0el {" .. displayRes .. "}", 0)
	mer:fixCursor()
	mer.editor:setReadOnly(true)
	theView:add(mer)
	reposME()

-- Any unhandled errors will cause LuaCAS Engine status to go NONE (red)
end