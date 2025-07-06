_G.darkMode = (var.recall("dark_mode") == 1)
_G.showLaunchAnimation = (var.recall("nLuaCAS_launch_anim_pref") == 1)

function getStringWidth(text)
    return platform.withGC(function(gc) return gc:getStringWidth(text) end, text)
end
_G.precisionInputActive = false
_G.showComplex = (var.recall("nLuaCAS_complex_pref") == 1)
-- Launch animation globals
local n_logo = image.new(_R.IMG.n_logo)
local luacas_text = image.new(_R.IMG.luacas_text)
local scaleFactorLogo = 0.1 -- Adjusted smaller n logo
local scaleFactorText = 0.035 -- Adjusted smaller LuaCAS text to match n height
local nW, nH = image.width(n_logo) * scaleFactorLogo, image.height(n_logo) * scaleFactorLogo
local luaW, luaH = image.width(luacas_text) * scaleFactorText, image.height(luacas_text) * scaleFactorText
local launchStartTime = timer.getMilliSecCounter()
-- Recall launch animation preference: 1 for show, 0 for hide. Default to show if not set.

local showLaunchAnim = _G.showLaunchAnimation -- Initialize local variable based on global preference
local logoX, textX = -100, -300
local overlayAlpha = 1.0
local overlayRegion = {x=270, y=8, w=90, h=24} -- Position this based on the layout
local cursorInsideOverlay = false


function syncCategoryFromStorage()
    local cat = nil
    if var and type(var.recall) == "function" then
        cat = var.recall("current_constant_category")
    end

    if cat and type(cat) == "string" then
        _G.current_constant_category = cat
        _G.currentConstCategory = cat
        print("[STATE] Recalled category from storage:", cat)
    else
        local fallback = gui.get_current_constant_category()
        _G.current_constant_category = fallback
        _G.currentConstCategory = fallback
        print("[STATE] No stored category, using default:", fallback)
    end

    -- Always update GUI button text if it exists
    if _G.categoryBtn then
        _G.categoryBtn.text = _G.currentConstCategory
        print("[DEBUG] Category button updated to:", _G.currentConstCategory)
    end
end

function setupLaunchAnimation()
    if showLaunchAnim then
        -- Start a timer to drive the animation. You need a variable to store the timer ID.
        animationTimerId = timer.start(10) -- Set a small interval like 10ms for smooth animation
    else
        -- If animation is off, immediately make the editor visible
        if fctEditor and fctEditor.editor then
            fctEditor.editor:setVisible(true)
        end
        platform.window:invalidate() -- Force a redraw to ensure editor is shown
    end
end
var = var or {}
var.store = var.store or {}
local parser = rawget(_G, "parser")
if not parser or not parser.parse then
  error("parser module or parser.parse not defined — ensure parser.lua is loaded before gui.lua")
end
local parse = parser.parse
local simplify = rawget(_G, "simplify")
local errors = _G.errors

-- Ensure getLocaleText exists, fallback to identity
local getLocaleText = rawget(_G, "getLocaleText") or function(key) return key end

_G.autoDecimal = false
_G.settingsBtnRegion = {x = 0, y = 0, w = 32, h = 32}
-- Modal flag for settings
_G.showSettingsModal = false
_G.showHelpModal = false
_G.showStartupHint = true
if var and var.recall and var.recall("hide_startup_hint") == 1 then
    _G.showStartupHint = false
end
_G.switchPressed = false
_G.modalETKButton = nil
_G.modalCloseBtnRegion = {x = 0, y = 0, w = 24, h = 24}
-- Compatibility hack: unpack became table.unpack in newer Lua, because reasons
unpack = unpack or table.unpack

-- ====== Embedded Standalone ETK-style Button Widget ======

Widgets = {}
function applyEditorColors()
    if fctEditor and fctEditor.editor then
        local bg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
        local text = _G.darkMode and {255, 255, 255} or {0, 0, 0}
        local border = _G.darkMode and {100, 100, 100} or {0, 0, 0}

        if fctEditor.editor.setBackgroundColor then
            fctEditor.editor:setBackgroundColor(table.unpack(bg))
        end
        if fctEditor.editor.setTextColor then
            fctEditor.editor:setTextColor(table.unpack(text))
        end
        if fctEditor.editor.setBorderColor then
            fctEditor.editor:setBorderColor(table.unpack(border))
        end
        if fctEditor.editor.setOpaque then
            fctEditor.editor:setOpaque(true)
        end
    end
end
-- Helper for unpacking color
function unpackColor(t)
  return t[1], t[2], t[3]
end

-- Helper for simple dimension (width, height)
function Dimension(w, h)
  return { width = w, height = h }
end

-- Helper event dispatcher
function CallEvent(obj, name)
  if obj[name] then obj[name](obj) end
end

-- ETK-style Button class
Widgets.Button = class(Widget)
local Button = Widgets.Button

Button.defaultStyle = {
  textColor       = {{000,000,000},{000,000,000}},
  backgroundColor = {{248,252,248},{248,252,248}},
  borderColor     = {{136,136,136},{160,160,160}},
  focusColor      = {{040,148,184},{000,000,000}},
  defaultWidth  = 48,
  defaultHeight = 27,
  font = {
    serif="sansserif",
    style="r",
    size=10
  }
}

function Button:init(arg)	
  self.text = arg.text or "Button"
  local style = arg.style or Button.defaultStyle or {
    textColor       = {{0,0,0},{0,0,0}},
    backgroundColor = {{248,252,248},{248,252,248}},
    borderColor     = {{136,136,136},{160,160,160}},
    focusColor      = {{40,148,184},{0,0,0}},
    defaultWidth  = 48,
    defaultHeight = 27,
    font = {
      serif="sansserif",
      style="r",
      size=10
    }
  }
  self.style = style
  self.dimension = arg.position or Dimension(style.defaultWidth or 48, style.defaultHeight or 27)
  Widget.init(self, nil, self.dimension.width or style.defaultWidth, self.dimension.height or style.defaultHeight)
  self.meDown = false
  self.hasFocus = false
  self.parent = arg.parent or nil
  self.onAction = arg.onAction or nil
end

function Button:prepare(gc)
  local font = self.style.font
  gc:setFont(font.serif, font.style, font.size)
  self.dimension.width = gc:getStringWidth(self.text) + 10
end

function Button:draw(gc, x, y, width, height, isColor)
  if self.meDown then
    y = y + 1
  end

  local color = isColor and 1 or 2
  local style = self.style or Button.defaultStyle

  local isDark = _G.darkMode
local colorSet = isDark and {
    backgroundColor = {50, 50, 50},
    textColor = {220, 220, 220},
    borderColor = {100, 100, 100},
    focusColor = {80, 160, 220}
} or {
    backgroundColor = {248, 252, 248},
    textColor = {0, 0, 0},
    borderColor = {136, 136, 136},
    focusColor = {40, 148, 184}
}

local bg = colorSet.backgroundColor
local tc = colorSet.textColor
local bc = colorSet.borderColor
local fc = colorSet.focusColor

  gc:setColorRGB(unpackColor(bg))
  gc:fillRect(x + 2, y + 2, width - 4, height - 4)

  gc:setColorRGB(unpackColor(tc))
  gc:drawString(self.text, x + 5, y + 3, "top")

  if self.hasFocus then
    gc:setColorRGB(unpackColor(fc))
    gc:setPen("medium", "smooth")
  else
    gc:setColorRGB(unpackColor(bc))
    gc:setPen("thin", "smooth")
  end

  gc:fillRect(x + 2, y, width - 4, 2)
  gc:fillRect(x + 2, y + height - 2, width - 4, 2)
  gc:fillRect(x, y + 2, 1, height - 4)
  gc:fillRect(x + 1, y + 1, 1, height - 2)
  gc:fillRect(x + width - 1, y + 2, 1, height - 4)
  gc:fillRect(x + width - 2, y + 1, 1, height - 2)

  if self.hasFocus then
    gc:setColorRGB(unpackColor(style.focusColor[color]))
  end

  gc:setPen("thin", "smooth")
end

function Button:doAction()
  if self.parent and self.parent.invalidate then
    self.parent:invalidate()
  end
  if self.onAction then
    self.onAction(self)
  else
    CallEvent(self, "onAction")
  end
end

function Button:onMouseDown()
  self.meDown = true
end

function Button:onMouseUp(x, y, onMe)
  self.meDown = false
  if onMe then
    self:doAction()
  end
end

function Button:enterKey()
  self:doAction()
end

-- ====== END Standalone Button Widget ======
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
			o:onMouseDown(x - o.x, y - o.y)
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
 
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
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
-- TextBox widget for text input
TextBox = class(Widget)
function TextBox:init(view, x, y, w, h, text)
    self.text = text or ""
    self.cursor = #self.text
    self.focused = false
    self.acceptsFocus = true
    self.acceptsChar = true
    self.acceptsBackspace = true
    self.acceptsEnter = true
    Widget.init(self, view, x, y, w, h)
end

function TextBox:paint(gc, focused)
    -- Draw border
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(self.x, self.y, self.w, self.h)
    
    -- Draw background
    if focused then
        gc:setColorRGB(255, 255, 255)
    else
        gc:setColorRGB(240, 240, 240)
    end
    gc:fillRect(self.x + 1, self.y + 1, self.w - 2, self.h - 2)
    
    -- Draw text
    gc:setColorRGB(0, 0, 0)
    gc:drawString(self.text, self.x + 3, self.y + 3, "top")
    
    -- Draw cursor if focused
    if focused then
        local cursorX = self.x + 3 + getStringWidth(string.sub(self.text, 1, self.cursor))
        gc:drawLine(cursorX, self.y + 2, cursorX, self.y + self.h - 3)
    end
end

function TextBox:charIn(char)
    self.text = string.sub(self.text, 1, self.cursor) .. char .. string.sub(self.text, self.cursor + 1)
    self.cursor = self.cursor + 1
    self.view:invalidate()
end

function TextBox:backspaceKey()
    if self.cursor > 0 then
        self.text = string.sub(self.text, 1, self.cursor - 1) .. string.sub(self.text, self.cursor + 1)
        self.cursor = self.cursor - 1
        self.view:invalidate()
    end
end

function TextBox:setText(text)
    self.text = text or ""
    self.cursor = #self.text
    self.view:invalidate()
end

function TextBox:getText()
    return self.text
end

-- CheckBox widget
CheckBox = class(Widget)
function CheckBox:init(view, x, y, text, checked)
    self.textid = text
    self.text = getLocaleText(text)
    self.checked = checked or false
    self.acceptsFocus = true
    self.acceptsEnter = true
    
    local boxSize = 12
    local textWidth = getStringWidth(self.text)
    local w = boxSize + 5 + textWidth
    local h = math.max(boxSize, getStringHeight(self.text))
    
    Widget.init(self, view, x, y, w, h)
end

function CheckBox:paint(gc, focused)
    local boxSize = 12
    
    -- Draw checkbox
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(self.x, self.y, boxSize, boxSize)
    gc:setColorRGB(255, 255, 255)
    gc:fillRect(self.x + 1, self.y + 1, boxSize - 2, boxSize - 2)
    
    -- Draw check mark if checked
    if self.checked then
        gc:setColorRGB(0, 0, 0)
        gc:drawLine(self.x + 2, self.y + 6, self.x + 5, self.y + 9)
        gc:drawLine(self.x + 5, self.y + 9, self.x + 10, self.y + 3)
    end
    
    -- Draw text
    gc:setColorRGB(0, 0, 0)
    gc:drawString(self.text, self.x + boxSize + 5, self.y, "top")
    
    -- Draw focus indicator
    if focused then
        gc:setColorRGB(0, 0, 255)
        gc:drawRect(self.x - 1, self.y - 1, self.w + 2, self.h + 2)
    end
end

function CheckBox:enterKey()
    self.checked = not self.checked
    self.view:invalidate()
end

-- --- START OF CHANGE ---
-- Renamed from CheckBox:mouseDown to CheckBox:onMouseUp
function CheckBox:onMouseUp(x, y)
    print("CheckBox:onMouseUp called for:", self.text)
    print("Received x:", x, " type:", type(x))
    print("Received y:", y, " type:", type(y))
    print("Before toggle, checked:", self.checked)
    self.checked = not self.checked
    print("After toggle, checked:", self.checked)
    self.view:invalidate()
    print("View invalidated.")
end
-- --- END OF CHANGE ---

-- Dialog base class, inheriting from Widget
Dialog = class(Widget)
function Dialog:init(view, config)
    -- Default configuration values for the dialog
    local title = config.title or "Dialog"
    local w = config.width or 300
    local h = config.height or 200
    local elements = config.elements or {}
    self.onClose = config.onClose -- Store the custom onClose function

    -- Calculate dialog position to be centered on the screen
    local x = math.floor((platform.window:width() - w) / 2)
    local y = math.floor((platform.window:height() - h) / 2)

    -- Initialize the base Widget properties
    Widget.init(self, view, x, y, w, h)

    self.title = title
    self.modal = true         -- Dialog is modal, meaning it captures all input
    self.visible = true       -- Dialog starts as visible
    self.acceptsFocus = true  -- Dialog can gain keyboard focus
    self.acceptsEscape = true -- Allow Escape key to close the dialog
    self.widgets = {}         -- Table to hold child widgets managed by this dialog
    self.result = nil         -- To store dialog's return value (e.g., true for OK, false for Cancel)
    self.namedWidgets = {}    -- NEW: Table to store child widgets by their 'name' property

    for i, elem_config in ipairs(elements) do
        local widget
        -- Instantiate widget types based on their 'type' property in the config
        if elem_config.type == "TextLabel" then
            widget = TextLabel(view, elem_config.x, elem_config.y, elem_config.text)
        elseif elem_config.type == "TextButton" then
            local original_command = elem_config.command or function(dlg_ref, btn_ref) end -- Default command, receives dialog and button
            widget = TextButton(view, elem_config.x, elem_config.y, elem_config.text,
                function(btn_self) -- 'btn_self' is the TextButton instance being clicked
                    -- Pass the dialog instance (self) and the button instance (btn_self) to the original command
                    original_command(self, btn_self)
                    -- If the button is configured to close the dialog, call close()
                    if elem_config.closesDialog then
                        self:close(true)
                    end
                end)
        elseif elem_config.type == "CheckBox" then
            widget = CheckBox(view, elem_config.x, elem_config.y, elem_config.text, elem_config.checked)
            -- The existing special handling for checkbox by 'checkbox_' prefix can remain or be unified
        end

        -- If a widget was successfully created, add it to the dialog's managed widgets
        if widget then
            self:addWidget(widget)
            -- NEW: Store a reference to the widget by its 'name' property for easy access
            if elem_config.name then
                self.namedWidgets[elem_config.name] = widget
            end
        end
    end
end

-- Paint method for the Dialog. This draws the dialog frame and its contents.
function Dialog:paint(gc, focused)
    -- Draw a subtle shadow effect
    gc:setColorRGB(128, 128, 128)
    gc:fillRect(self.x + 3, self.y + 3, self.w, self.h)

    -- Draw dialog background (light gray)
    gc:setColorRGB(240, 240, 240)
    gc:fillRect(self.x, self.y, self.w, self.h)

    -- Draw dialog border (black)
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(self.x, self.y, self.w, self.h)

    -- Draw title bar (dark blue)
    gc:setColorRGB(0, 0, 128)
    gc:fillRect(self.x + 1, self.y + 1, self.w - 2, 20)
    gc:setColorRGB(255, 255, 255) -- White text for title
    gc:drawString(self.title, self.x + 5, self.y + 4, "top")

    -- Draw a line under the title bar
    gc:setColorRGB(0, 0, 0)
    gc:drawLine(self.x + 1, self.y + 21, self.x + self.w - 2, self.y + 21)

    -- Paint all child widgets relative to the dialog's position
    for _, widget in ipairs(self.widgets) do
        if widget.visible then
            -- Pass the correct focused state to the child widget
            local is_child_focused = (self.view:getFocus() == widget)
            widget:paint(gc, is_child_focused)
        end
    end
end

-- Adds a child widget to the dialog's management.
function Dialog:addWidget(widget)
    table.insert(self.widgets, widget)
    widget.parent = self -- Set the dialog as the widget's parent
    -- Adjust widget's position to be relative to the dialog's top-left corner
    -- assuming widget.xOrig and widget.yOrig store initial offsets from dialog
    widget.x = self.x + widget.xOrig
    widget.y = self.y + widget.yOrig
    self.view:add(widget)     -- Crucial: Add the child widget to the main view for event handling
    self.view:repos(widget)   -- Ask the view to reposition it if necessary (e.g., for layout constraints)
end

-- Activates the dialog, making it visible and focusable.
function Dialog:activate()
    self.visible = true
    -- Set this dialog as the active modal dialog for the view
    self.view.activeModalDialog = self -- ADD THIS LINE

    -- Set focus to the first focusable widget within the dialog (for keyboard nav)
    for _, widget in ipairs(self.widgets) do
        if widget.acceptsFocus then
            self.view:setFocus(widget)
            break
        end
    end
    self.view:invalidate() -- Request a screen redraw
end

-- Closes the dialog, making it invisible and removing its widgets from the view.
function Dialog:close(result)
    self.result = result
    self.visible = false
    -- Remove the dialog itself from the main view's tracking
    self.view:remove(self)
    -- Remove all child widgets from the main view's tracking
    for _, widget in ipairs(self.widgets) do
        self.view:remove(widget)
    end
    -- Call the custom onClose callback function if provided
    if self.onClose then
        self.onClose(self, result)
    end
    self.view:invalidate() -- Request a screen redraw
end

-- In your Dialog class definition (e.g., in gui.lua or dialog.lua)

-- Corrected Dialog:onMouseDown
function Dialog:onMouseDown(x, y)
    -- Iterate through widgets from top to bottom (reverse order)
    for i = #self.widgets, 1, -1 do
        local widget = self.widgets[i]
        -- Check if widget is visible, accepts focus, and contains the click coordinates
        if widget.visible and widget.acceptsFocus and widget:contains(x, y) then
            -- If the widget has its own onMouseDown handler, call it, passing coordinates relative to the widget
            if widget.onMouseDown then
                widget:onMouseDown(x - widget.x, y - widget.y)
            end
            -- Set focus to the clicked widget and invalidate the window for redraw
            self.view:setFocus(widget)
            self.view:invalidate()
            return -- Exit after handling the click on one widget
        end
    end
    -- If no child widget was clicked, check if the dialog itself was clicked
    if self:contains(x, y) then
        self.view:setFocus(self)
        self.view:invalidate()
    end
end

-- Corrected Dialog:onMouseUp
function Dialog:onMouseUp(x, y)
    -- Iterate through widgets from top to bottom (reverse order)
    for i = #self.widgets, 1, -1 do
        local widget = self.widgets[i]
        -- Check if widget is visible, contains the release coordinates, and has an onMouseUp handler
        if widget.visible and widget:contains(x, y) and widget.onMouseUp then
            -- Call the widget's onMouseUp handler, passing relative coordinates and whether it was released inside
            widget:onMouseUp(x - widget.x, y - widget.y, widget:contains(x,y))
            return -- Exit after handling the release on one widget
        end
    end
end

-- Handles the Escape key press for the dialog (if acceptsEscape is true).
function Dialog:escapeHandler()
    if self.acceptsEscape then
        self:close(false) -- False indicates dialog was cancelled/escaped
    end
end
-- Closes the dialog, making it invisible and removing its widgets from the view.
function Dialog:close(result)
    self.result = result
    self.visible = false

    -- CRITICAL FIX: Reset the active modal dialog in the view
    if self.view.activeModalDialog == self then
        self.view.activeModalDialog = nil
    end

    -- Remove the dialog itself from the main view's tracking
    self.view:remove(self)

    -- Remove all child widgets from the main view's tracking
    for _, widget in ipairs(self.widgets) do
        self.view:remove(widget)
    end

    -- Call the custom onClose callback function if provided
    if self.onClose then
        self.onClose(self, result)
    end
    self.view:invalidate() -- Request a screen redraw
end


MenuWidget = class(Widget)

function MenuWidget:init(view, x, y, items, onSelect)
    local w = 120
    local h = #items * 22
    Widget.init(self, view, x, y, w, h)
    self.items = items or {}
    self.selected = 1
    self.onSelect = onSelect or function(idx, text) end
    self.visible = true
    self.acceptsFocus = true
    self.acceptsArrowUp = true
    self.acceptsArrowDown = true
    self.acceptsEnter = true
    self.acceptsEscape = true
    self.muted = false
    self.submenus = nil
end

function MenuWidget:paint(gc, focused)
    if not self.visible then return end

    -- Menu background - because invisible menus are so last century
    local bgColor = _G.darkMode and {40, 40, 40} or {255, 255, 255}
    if self.muted then for i=1,3 do bgColor[i] = bgColor[i] * 0.6 end end
    gc:setColorRGB(table.unpack(bgColor))
    gc:fillRect(self.x, self.y, self.w, self.h)

    -- Menu border - the thin line between chaos and order
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(self.x, self.y, self.w, self.h)

    -- Menu items - the actual reason this thing exists
    for i, text in ipairs(self.items) do
        local itemY = self.y + (i-1) * 22

        -- Highlight selected item
        if i == self.selected then
            gc:setColorRGB(180, 200, 255)
            gc:fillRect(self.x + 1, itemY + 1, self.w - 2, 20)
        end

        gc:setFont("sansserif", "r", 11)
        gc:setColorRGB(_G.darkMode and 180 or 32, _G.darkMode and 180 or 32, _G.darkMode and 210 or 32)

        -- Decorative Icon on root menu only
        if self.level == 1 then
            -- Precise vertical centering for icon and text
            local iconX = self.x + 6
            local iconText = ""
            if text == "Calculus" then
                iconText = "∫"
            elseif text == "Solve" then
                iconText = "x"
            elseif text == "Settings" then
                iconText = "S"
            elseif text == "Help" then
                iconText = "?"
            end
            gc:setFont("sansserif", "b", 10)
            local ih = gc:getStringHeight(iconText)
            gc:setFont("sansserif", "r", 11)
            local th = gc:getStringHeight(text)
            local iconY = itemY + (th - ih) / 2 - 1
            gc:setFont("sansserif", "b", 10)
            gc:drawString(iconText, iconX, iconY, "top")
            gc:setFont("sansserif", "r", 11)
            gc:drawString(text, self.x + 22, itemY - 1, "top")
        else
            gc:drawString(text, self.x + 12, itemY - 1, "top")
        end

        if self.submenus and self.submenus[text] then
            gc:setFont("sansserif","b",11)
            local arrowCol = _G.darkMode and {200,200,200} or {64,64,64}
            gc:setColorRGB(table.unpack(arrowCol))
            gc:drawString("▶", self.x + self.w - 12, itemY - 1, "top")
        end
    end
end

function MenuWidget:onMouseDown(view, window, x, y)
    if not self:contains(x + self.x, y + self.y) then return end
    
    local relY = y
    local idx = math.floor(relY / 22) + 1
    
    if idx >= 1 and idx <= #self.items then
        self.selected = idx
        if self.onSelect then 
            self.onSelect(idx, self.items[idx]) 
        end
    end
    
    local text = self.items[self.selected]
    -- Only hide when there is no submenu for this item
    if not (self.submenus and self.submenus[text]) then
        self.visible = false
        if self.view and self.view.invalidate then
            self.view:invalidate()
        end
    end
end

function MenuWidget:arrowUpHandler()
    self.selected = math.max(1, self.selected - 1)
    if self.view and self.view.invalidate then
        self.view:invalidate()
    end
end

function MenuWidget:arrowDownHandler()
    self.selected = math.min(#self.items, self.selected + 1)
    if self.view and self.view.invalidate then
        self.view:invalidate()
    end
end

function MenuWidget:enterHandler()
    if self.onSelect then 
        self.onSelect(self.selected, self.items[self.selected]) 
    end
    self.visible = false
    if self.view and self.view.invalidate then 
        self.view:invalidate() 
    end
end

function MenuWidget:escapeHandler()
    self.visible = false
    if self.view and self.view.invalidate then 
        self.view:invalidate() 
    end
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
    -- Set dark/light mode colors at initialization, safely and consistently
    if self.editor then
        local areaBg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
        local areaBorder = _G.darkMode and {100, 100, 100} or {0, 0, 0}
        local text = _G.darkMode and {255, 255, 255} or {0, 0, 0}
        if self.editor.setBackgroundColor then
            self.editor:setBackgroundColor(table.unpack(areaBg))
        end
        if self.editor.setTextColor then
            self.editor:setTextColor(table.unpack(text))
        end
        if self.editor.setBorderColor then
            self.editor:setBorderColor(table.unpack(areaBorder))
        end
        if self.editor.setOpaque then
            self.editor:setOpaque(true)
        end
    end
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
    if _G.menuStack and #_G.menuStack > 0 then
        local m = _G.menuStack[#_G.menuStack]
        m:arrowUpHandler()
        return
    end
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
    if _G.menuStack and #_G.menuStack > 0 then
        local m = _G.menuStack[#_G.menuStack]
        m:arrowDownHandler()
        return
    end
  if theView then
    on.backtabKey()
    if theView:getFocus() ~= fctEditor then on.backtabKey() end
    reposView()
  end
end

function on.arrowLeft()
    if _G.menuStack and #_G.menuStack > 0 then
        local depth = #_G.menuStack
        local m = _G.menuStack[depth]
        theView:remove(m)
        table.remove(_G.menuStack, depth)
        if _G.menuStack and #_G.menuStack > 0 then
            _G.menuStack[#_G.menuStack].muted = false
            theView:setFocus(_G.menuStack[#_G.menuStack])
        else
            _G.menuStack = nil
        end
        theView:invalidate()
        return
    end
  if theView then
    on.tabKey()
    reposView()
  end
end

function on.arrowRight()
    if _G.menuStack and #_G.menuStack > 0 then
        local m = _G.menuStack[#_G.menuStack]
        local idx = m.selected
        local text = m.items[idx]
        if m.onSelect then m.onSelect(idx, text) end
        return
    end
  if theView then
    on.backtabKey()
    reposView()
  end
end

function on.charIn(ch)
    if _G.showSettingsModal and _G.precisionInputActive and ch:match("%d") then
        var.store("nLuaCAS_precision_pref", tonumber(ch))
        _G.precisionInputActive = false
        platform.window:invalidate()
        return
    end
    if theView then theView:sendStringToFocus(ch) end
end

function on.tabKey()
  if theView then theView:tabForward(); reposView() end
end

function on.backtabKey()
  if theView then theView:tabBackward(); reposView() end
end

function on.enterKey()
    -- If a menu is open, treat Enter as submenu/selection trigger
    if _G.menuStack and #_G.menuStack > 0 then
        on.arrowRight()
        return
    end
  if not fctEditor or not fctEditor.getExpression then return end

  -- Recall the current constant category (do not set default here)
  local recalled = var.recall and var.recall("current_constant_category")
  if recalled ~= nil then
    current_constant_category = recalled
    print("[INIT] Recalled constant category: " .. tostring(current_constant_category))
  else
    print("[INIT] Recall failed or value was nil; skipping default set")
  end

  local input = fctEditor:getExpression()
  -- Check for custom snarky responses
  local joke = _G.errors.get(input)
  if joke then
    result = joke
    addME(input, result, "normal")
    if fctEditor and fctEditor.editor then
      fctEditor.editor:setText("")
      fctEditor:fixContent()
    end
    if platform and platform.window and platform.window.invalidate then
      platform.window:invalidate()
    end
    return
  end
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
  local function get_constant_value(fname)
    local physics_constants = _G.physics_constants or {}
    local avail = var.recall and var.recall("available_constants") or {}
    local is_enabled = (avail == nil) or (avail[fname] == true)
    -- Retrieve current category for this resolution
    local cat = var.recall and var.recall("current_constant_category")
    print("[DEBUG] Category set to:", tostring(cat))
    if physics_constants[fname]
      and is_enabled
      and physics_constants[fname].category == cat then
      return physics_constants[fname].value
    end
    return nil
  end
  local function eval_physics_func(fname)
    local physics_constants = _G.physics_constants or {}
    local avail = var.recall and var.recall("available_constants") or {}
    local is_enabled = (avail == nil) or (avail[fname] == true)
    -- Retrieve current category for this resolution
    local cat = var.recall and var.recall("current_constant_category")
    print("[DEBUG] Category set to:", tostring(cat))
    if physics_constants[fname]
      and is_enabled
      and physics_constants[fname].category == cat then
      return physics_constants[fname].value
    end
    return nil
  end

  local success, err = pcall(function()
    if input:sub(1,4) == "d/dx" or input:sub(1,4) == "d/dy" then
      local expr = input:match("d/d[xy]%((.+)%)")
      result = expr and derivative(expr, _G.__diff_var) or errors.invalid("diff")
      if result == errors.invalid("diff") then _G.luaCASerror = true end
    elseif input:sub(1,5) == "∂/∂x(" and input:sub(-1) == ")" then
      local expr = input:match("∂/∂x%((.+)%)")
      result = expr and derivative(expr, _G.__diff_var) or errors.invalid("diff")
      if result == errors.invalid("diff") then _G.luaCASerror = true end
    elseif input:match("^∂/∂[yz]%(.+%)$") then
      result = derivative(input, _G.__diff_var)
    elseif input:sub(1,3) == "∫(" and input:sub(-2) == ")x" then
      result = integrate(parse(input:sub(4, -3)))
    elseif input:sub(1,6) == "solve(" and input:sub(-1) == ")" then
      local eqn = input:match("solve%((.+)%)")
      if eqn and not eqn:find("=") then
        eqn = eqn .. "=0"
      end
      result = eqn and solve(parse(eqn)) or errors.invalid("solve")
      if result == errors.invalid("solve") then _G.luaCASerror = true end
    elseif input:sub(1,4) == "let" then
      result = define(input)
    elseif input:sub(1,7) == "expand(" and input:sub(-1) == ")" then
        local inner = input:match("expand%((.+)%)")
        result = inner and expand(parse(inner)) or errors.invalid("expand")
        if result == errors.invalid("expand") then _G.luaCASerror = true end
    elseif input:sub(1,5) == "subs(" and input:sub(-1) == ")" then
        local inner, varname, val = input:match("subs%(([^,]+),([^,]+),([^%)]+)%)")
        result = (inner and varname and val) and subs(parse(inner), varname, val) or errors.invalid("subs")
        if result == errors.invalid("subs") then _G.luaCASerror = true end
    elseif input:sub(1,7) == "factor(" and input:sub(-1) == ")" then
        local inner = input:match("factor%((.+)%)")
        result = inner and factor(parse(inner)) or errors.invalid("factor")
        if result == errors.invalid("factor") then _G.luaCASerror = true end
    elseif input:sub(1,4) == "gcd(" and input:sub(-1) == ")" then
        local a, b = input:match("gcd%(([^,]+),([^%)]+)%)")
        result = (a and b) and gcd(parse(a), parse(b)) or errors.invalid("gcd")
        if result == errors.invalid("gcd") then _G.luaCASerror = true end
    elseif input:sub(1,4) == "lcm(" and input:sub(-1) == ")" then
        local a, b = input:match("lcm%(([^,]+),([^%)]+)%)")
        result = (a and b) and lcm(parse(a), parse(b)) or errors.invalid("lcm")
        if result == errors.invalid("lcm") then _G.luaCASerror = true end
    elseif input:sub(1,7) == "trigid(" and input:sub(-1) == ")" then
        local inner = input:match("trigid%((.+)%)")
        result = inner and trigid(parse(inner)) or errors.invalid("trigid")
        if result == errors.invalid("trigid") then _G.luaCASerror = true end
    elseif input:match("%w+%(.+%)") then
      print("[DEBUG] Category set to:", var.recall("current_constant_category"))
      result = simplify.simplify(parse(input))
    elseif input:sub(1,9) == "simplify(" and input:sub(-1) == ")" then
      local inner = input:match("simplify%((.+)%)")
      print("[DEBUG] Category set to:", var.recall("current_constant_category"))
      result = inner and simplify.simplify(parse(inner)) or errors.invalid("simplify")
      if result == errors.invalid("simplify") then _G.luaCASerror = true end
    -- Fallback parser for diff(...) and integrate(...)
    elseif input:match("^diff%(([^,]+),([^,%)]+)%)$") then
      local a, b = input:match("^diff%(([^,]+),([^,%)]+)%)$")
      result = (a and b) and derivative(parse(a), b) or errors.invalid("diff")
      if result == errors.invalid("diff") then _G.luaCASerror = true end
    elseif _G.__diff_var then
      result = derivative(input, _G.__diff_var)
      _G.__diff_var = nil
    elseif input:match("^integrate%(([^,]+),([^,%)]+)%)$") then
      local a, b = input:match("^integrate%(([^,]+),([^,%)]+)%)$")
      result = (a and b) and integrate(parse(a), b) or errors.invalid("int")
      if result == errors.invalid("int") then _G.luaCASerror = true end
    else
      -- Try constant resolution
      local constval = get_constant_value(input)
      if constval ~= nil then
        result = constval
      else
        print("[DEBUG] Category set to:", var.recall("current_constant_category"))
        result = simplify.simplify(parse(input))
      end
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
function Dialog:paint(gc, focused)
    -- Draw shadow
    gc:setColorRGB(128, 128, 128)
    gc:fillRect(self.x + 3, self.y + 3, self.w, self.h)

    -- Draw dialog background
    gc:setColorRGB(240, 240, 240)
    gc:fillRect(self.x, self.y, self.w, self.h)

    -- Draw border
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(self.x, self.y, self.w, self.h)

    -- Draw title bar
    gc:setColorRGB(0, 0, 128)
    gc:fillRect(self.x + 1, self.y + 1, self.w - 2, 20)
    gc:setColorRGB(255, 255, 255)
    gc:drawString(self.title, self.x + 5, self.y + 4, "top")

    -- Draw title bar border
    gc:setColorRGB(0, 0, 0)
    gc:drawLine(self.x + 1, self.y + 21, self.x + self.w - 2, self.y + 21)

    -- Paint child widgets (from the dialog's perspective)
    for _, widget in ipairs(self.widgets) do
        if widget.visible then
            -- Pass the correct focused state for the child widget
            local is_child_focused = (self.view:getFocus() == widget)
            widget:paint(gc, is_child_focused)
        end
    end
end

function Dialog:addWidget(widget)
    table.insert(self.widgets, widget)
    widget.parent = self -- Set the dialog as the widget's parent
    -- Adjust widget's position relative to the dialog's top-left corner
    -- This assumes widgets are added with their absolute coordinates, then adjusted.
    widget.x = self.x + widget.xOrig
    widget.y = self.y + widget.yOrig
    self.view:add(widget) -- Add to main view for global event handling
    self.view:repos(widget) -- Reposition in case constraints are set
end

function Dialog:activate()
    self.visible = true
    -- No need to self.view:add(self) here if it's already added in on.paint if not existing.
    -- Set focus to the first focusable widget within the dialog if available
    for _, widget in ipairs(self.widgets) do
        if widget.acceptsFocus then
            self.view:setFocus(widget)
            break
        end
    end
    self.view:invalidate()
end

function Dialog:close(result)
    self.result = result
    self.visible = false
    -- Remove dialog and its child widgets from the main view's tracking
    self.view:remove(self) -- Remove dialog itself from view's widgetList/focusList
    for _, widget in ipairs(self.widgets) do
        self.view:remove(widget) -- Remove child widgets from view
    end
    if self.onClose then
        self.onClose(self, result)
    end
    self.view:invalidate()
end

function Dialog:onMouseDown(x, y)
    -- Check if click is on dialog itself
    if self:contains(x, y) then
        -- Pass event to child widgets
        for i = #self.widgets, 1, -1 do -- Iterate in reverse for topmost widget
            local widget = self.widgets[i]
            if widget.visible and widget:contains(x, y) and widget.acceptsMouse then
                widget:onMouseDown(x, y)
                self.view:setFocus(widget) -- Set focus to the clicked widget
                return
            end
        end
    end
end

function Dialog:onMouseUp(x, y)
    -- Pass event to child widgets
    for i = #self.widgets, 1, -1 do -- Iterate in reverse for topmost widget
        local widget = self.widgets[i]
        if widget.visible and widget:contains(x, y) and widget.onMouseUp then
            widget:onMouseUp(x, y)
            return
        end
    end
end

function Dialog:escapeHandler()
    -- If escape is pressed, close the dialog
    self:close(false) -- False indicates cancellation or escape
end
function on.mouseMove(x, y)
  if theView then theView:onMouseMove(x, y) end
end

function on.mouseDown(x, y)
  -- Modal close "X" button
  if _G.showSettingsModal and _G.modalCloseBtnRegion then
    local r = _G.modalCloseBtnRegion
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      _G.showSettingsModal = false
      platform.window:invalidate()
      return
    end
  end
  -- Close help modal and block background clicks
  if _G.showHelpModal then
      local r = _G.helpModalCloseBtnRegion
      if r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then
          _G.showHelpModal = false
          platform.window:invalidate()
      end
      return
  end
  -- Startup Hint modal block
  if _G.showStartupHint then
      local r = _G.hintDismissBtnRegion
      if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
          _G.showStartupHint = false
          platform.window:invalidate()
          return
      end
      if _G.startupDontShowBtn then
          local btnX = (scrWidth - 240) / 2 + 10
          local btnY = scrHeight - 90 - 80 + 90 - 22 - 10
          if x >= btnX and x <= btnX + 110 and y >= btnY and y <= btnY + 22 then
              _G.startupDontShowBtn:onMouseDown()
              platform.window:invalidate()
              return
          end
      end
  end
  -- Modal ETK Button mouseDown
  if _G.showSettingsModal and _G.modalETKButton then
    local btn = _G.modalETKButton
    local btnW = btn.dimension.width or 80
    local btnH = btn.dimension.height or 28
    local modalW, modalH = 200, 120
    local modalX = (scrWidth - modalW) / 2
    local modalY = (scrHeight - modalH) / 2
    local btnX = modalX + (modalW - btnW) / 2
    local btnY = modalY + 54
    if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
      btn:onMouseDown()
      platform.window:invalidate()
      return
    end
  end
  -- Toggle switch press effect when settings modal is open
  if _G.showSettingsModal and _G.switchRegion then
    local r = _G.switchRegion
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      _G.switchPressed = true
      platform.window:invalidate()
      return
    end
  end
  if theView then theView:onMouseDown(x, y) end
end
function on.mouseUp(x, y)
    -- This block should only CREATE and ACTIVATE the settings dialog if it needs to be shown.
    -- The painting should happen in on.paint.
    print("\n--- on.mouseUp event ---") -- <--- IS THIS SHOWING?
    print("Current activeModalDialog (on entry):", tostring(theView.activeModalDialog)) -- <--- IS THIS SHOWING?
    if theView then
        if theView.activeModalDialog then
            -- If a modal dialog is active, send all mouse events directly to it
            theView.activeModalDialog:onMouseUp(x, y)
            return -- Crucial: stop further processing if a modal dialog handled it
        else
            -- Otherwise, let the normal view handle it
            theView:onMouseUp(x, y)
        end
    end
    

    -- Similar for the Help Dialog
    if _G.showHelpModal then
        if not _G.helpDialog then
            -- Create the help dialog only once
            -- ... (your existing dialog creation code, without _G.helpDialog:paint) ...

            -- Ensure it's added to the view and activated when created
            theView:add(_G.helpDialog)
            _G.helpDialog:activate()
        end
        -- Remove the _G.helpDialog:paint(gc, true) line from here!
    end
    
    -- Similar for the Startup Hint Dialog
    if var and var.recall and var.recall("hide_startup_hint") ~= 1 and _G.showStartupHint then
        if not _G.startupHintDialog then
            -- Create the startup hint dialog only once
            -- ... (your existing dialog creation code, without _G.startupHintDialog:paint) ...

            -- Ensure it's added to the view and activated when created
            theView:add(_G.startupHintDialog)
            _G.startupHintDialog:activate()
        end
        -- Remove the _G.startupHintDialog:paint(gc, true) line from here!
    end
    
    -- This line is correct and should remain. It dispatches the mouse event
    -- to the appropriate UI element, including any active dialog.
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

        -- Vertical scroll bar for history (because scrolling is still a thing)
        sbv = VScrollBar(theView, 0, -1, 5, scrHeight + 1)
        sbv:setHConstraints("right", 0)
        theView:add(sbv)
        

        -- Input editor at bottom (MathEditor) - the star of the show
        fctEditor = MathEditor(theView, 2, border, scrWidth - 4 - sbv.w, 30, "")
        
        -- Apply dark/light mode colors because apparently consistency matters
        if fctEditor and fctEditor.editor then
            local bg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
            if fctEditor.editor.setBackgroundColor then
                fctEditor.editor:setBackgroundColor(table.unpack(bg))
            end
            local text = _G.darkMode and {255, 255, 255} or {0, 0, 0}
            local border = _G.darkMode and {100, 100, 100} or {0, 0, 0}
            if fctEditor.editor.setTextColor then
                fctEditor.editor:setTextColor(table.unpack(text))
            end
            if fctEditor.editor.setBorderColor then
                fctEditor.editor:setBorderColor(table.unpack(border))
            end
        end
        
        fctEditor:setHConstraints("justify", 1)
        fctEditor:setVConstraints("bottom", 1)
        fctEditor.editor:setSizeChangeListener(function(editor, w, h)
            return resizeME(editor, w, h)
        end)
        theView:add(fctEditor)
        fctEditor.result = res
        fctEditor.editor:setText("")
        fctEditor:fixContent()

        -- First-focus is input editor (as it should be)
        theView:setFocus(fctEditor)

        -- Sync category state and update button after GUI is ready
        syncCategoryFromStorage()
        if _G.categoryBtn then
            _G.categoryBtn.text = _G.currentConstCategory
        end
        
        inited = true
    end

    toolpalette.enableCopy(true)
    toolpalette.enablePaste(true)
end


local function addStringToFctEditor(actionString)
    -- Assuming _G.fctEditor is the global MathEditor instance (or similar)
    
    if _G.fctEditor then
        _G.fctEditor:addString(actionString)
        -- Invalidate the window to ensure UI updates, as the system toolpalette doesn't
        -- automatically trigger redraws for the custom UI elements.
        platform.window:invalidate()
    else
        print("Error: _G.fctEditor not available to add string: " .. actionString)
    end
end

local function showSettingsModal()
    _G.showSettingsModal = true
    platform.window:invalidate() -- Invalidate to show the modal
end

local function showHelpModal()
    _G.showHelpModal = true
    platform.window:invalidate() -- Invalidate to show the modal
end

-- Handler function for toolpalette menu items
local function toolpaletteMenuHandler(toolboxName, menuItemName)
    if toolboxName == "Calculus" then
        if menuItemName == "Differentiate" then
            addStringToFctEditor("d/dx()")
        elseif menuItemName == "Integrate" then
            addStringToFctEditor("∫(,)")
        elseif menuItemName == "Abs" then
            addStringToFctEditor("abs()")
        elseif menuItemName == "Factorial" then
            addStringToFctEditor("factorial(")
        elseif menuItemName == "Empty Matrix" then
            addStringToFctEditor("[[,],[,]]")
        elseif menuItemName == "Taylor Series" then
            addStringToFctEditor("series(f,x,a,n)")
        elseif menuItemName == "Fourier Series" then
            addStringToFctEditor("series(f,x,a,n)")
        elseif menuItemName == "Maclaurin Series" then
            addStringToFctEditor("series(f,x,0,n)")
        end
    elseif toolboxName == "Solve" then
        if menuItemName == "Solve Equation" then
            addStringToFctEditor("solve(")
        end
    elseif toolboxName == "App Options" then
        if menuItemName == "Settings" then
            showSettingsModal()
        elseif menuItemName == "Help" then
            showHelpModal()
        end
    end
end

-- Correct menu structure for toolpalette.register
local myToolPaletteMenuStructure = {
    {"Calculus", -- First toolbox
        {"Differentiate", toolpaletteMenuHandler},
        {"Integrate", toolpaletteMenuHandler},
        {"Abs", toolpaletteMenuHandler},
        {"Factorial", toolpaletteMenuHandler},
        {"Empty Matrix", toolpaletteMenuHandler},
        "-", -- Separator
        {"Taylor Series", toolpaletteMenuHandler},
        {"Fourier Series", toolpaletteMenuHandler},
        {"Maclaurin Series", toolpaletteMenuHandler},
    },
    {"Solve", -- Second toolbox
        {"Solve Equation", toolpaletteMenuHandler},
    },
    {"App Options", -- Third toolbox
        {"Settings", toolpaletteMenuHandler},
        {"Help", toolpaletteMenuHandler},
    }
}

-- Register the tool palette
toolpalette.register(myToolPaletteMenuStructure)






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
  setupLaunchAnimation()
end

dispinfos = true

-- The main UI rendering phase: draws status, output, and all widgets.
-- If you’re looking for where the magic (or horror) happens, it’s here.
function on.paint(gc)
    -- Launch animation block (runs before normal UI)
    if showLaunchAnim then
        local now = timer.getMilliSecCounter()
        local dt = now - launchStartTime

        -- Hide the D2Editor while launch animation is running
        if fctEditor and fctEditor.editor then
            fctEditor.editor:setVisible(false)
        end

        -- White background
        gc:setColorRGB(255, 255, 255)
        gc:fillRect(0, 0, scrWidth, scrHeight)

        -- Ensure assets exist
        -- This block should be inside the on.timer() function or wherever the animation rendering happens
if showLaunchAnim then -- Add this conditional check here
    if n_logo and luacas_text then

        local dt = timer.getMilliSecCounter() - launchStartTime -- Make sure dt is defined if not already

        -- Animate n_logo: from off-screen right to x = 50
        local logoStartX = scrWidth + 100 -- Ensure scrWidth is accessible or defined
        local logoEndX = 20
        if dt < 1000 then
            logoX = logoStartX - (dt / 1000) * (logoStartX - logoEndX)
        else
            logoX = logoEndX
        end

        -- Animate luacas_text: from off-screen right to x = close to n_logo, starts after n_logo
        local textStartX = scrWidth + 300
        -- Use the same scale factors as globals for animation
        local logoWidth, logoHeight = image.width(n_logo) * scaleFactorLogo, image.height(n_logo) * scaleFactorLogo
        local textWidth, textHeight = image.width(luacas_text) * scaleFactorText, image.height(luacas_text) * scaleFactorText
        local textEndX = logoEndX + logoWidth + 30
        if dt >= 1000 and dt < 2000 then
            local textDt = dt - 1000
            textX = textStartX - (textDt / 1000) * (textStartX - textEndX)
        elseif dt >= 2000 then
            textX = textEndX
        end

        -- Draw images if within their time windows, scale logo and text to match global scaling
        local baseY = 100
        local baseYText = 77

        if dt >= 0 then
            gc:drawImage(n_logo, logoX, baseY, logoWidth, logoHeight)
        end
        if dt >= 100 then
            gc:drawImage(luacas_text, textX, baseYText, textWidth, textHeight)
        end

        -- End animation after both complete
        if dt >= 2500 then
            showLaunchAnim = false -- This will effectively stop the animation for subsequent frames
            -- Restore D2Editor visibility after animation ends
            if fctEditor and fctEditor.editor then
                fctEditor.editor:setVisible(true)
            end
            timer.stop(tick) -- Assuming 'tick' is the timer ID
            platform.window:invalidate()
        end
    end

    -- Remove invalidate from here; handled by timer for smooth animation
    return
else -- If showLaunchAnim is false, just immediately set it to false and stop the timer
    showLaunchAnim = false -- Ensure it's false to prevent future animation attempts
    timer.stop(tick) -- Stop the animation timer immediately if it's not meant to run
    -- Restore D2Editor visibility immediately
    if fctEditor and fctEditor.editor then
        fctEditor.editor:setVisible(true)
    end
    platform.window:invalidate() -- Force a redraw if needed
    return -- Exit the on.timer function
end
end

    if not inited then
        initGUI()
        initFontGC(gc)
        strFullHeight = gc:getStringHeight("H")
        strHeight = strFullHeight - 3
    end
    if inited then
        -- Global dark mode background
        local globalBg = _G.darkMode and {20, 20, 20} or {255, 255, 255}
        gc:setColorRGB(unpackColor(globalBg))
        gc:fillRect(0, 0, scrWidth, scrHeight)

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
            -- (Logo image block removed for customization)
        end
        -- Output string fallback for "main" view
        if true then -- "main" view block
            local output = fctEditor and fctEditor.result
            local outputStr = (output and output ~= "") and output or "(no output)"
            -- Draw output in white for dark mode, black for light mode
            gc:setColorRGB(_G.darkMode and 255 or 0, _G.darkMode and 255 or 0, _G.darkMode and 255 or 0)
            gc:drawString(outputStr, 10, scrHeight - 25, "top")
        end
        -- Draw custom settings icon button at top right if modal not open
        
        theView:paint(gc)

        -- Draw the bottom input area background fully respecting dark mode (after theView:paint)
        do
            -- Use pure white and black in light mode, no blue tint
            local areaBg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
            local areaBorder = _G.darkMode and {100, 100, 100} or {0, 0, 0}
            local boxY = fctEditor.y - 2
            local boxH = fctEditor.h + 4
            gc:setColorRGB(table.unpack(areaBg))
            gc:fillRect(0, boxY, scrWidth, boxH)
            gc:setColorRGB(table.unpack(areaBorder))
            gc:drawRect(0, boxY, scrWidth, boxH)
            -- Immediately override editor background, text, and border for safety and consistency
            if fctEditor and fctEditor.editor and fctEditor.editor.setBackgroundColor then
                local bg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
                local text = _G.darkMode and {255, 255, 255} or {0, 0, 0}
                local border = _G.darkMode and {100, 100, 100} or {0, 0, 0}
                fctEditor.editor:setBackgroundColor(table.unpack(bg))
                if fctEditor.editor.setTextColor then
                    fctEditor.editor:setTextColor(table.unpack(text))
                end
                if fctEditor.editor.setBorderColor then
                    fctEditor.editor:setBorderColor(table.unpack(border))
                end
            end
        end

        -- Draw settings modal if enabled (block moved to end)
    end
    
-- Replace the entire manual drawing block for _G.showSettingsModal
if _G.showSettingsModal then
    -- Create the settings dialog only once
    if not _G.settingsDialog then
        -- Define base positions for elements relative to the dialog's top-left corner (0,0)
        local labelCol1X = 20    -- X-coordinate for labels in the first column
        local valueCol1X = 120   -- X-coordinate for buttons/values, estimated for alignment
        local lineHeight = 28    -- Vertical spacing between lines of elements
        local btnW, btnH = 48, 22 -- Standard button width and height
        if fctEditor and fctEditor.editor then -- Add nil check for robustness
            fctEditor.editor:setVisible(false)
        end

        _G.settingsDialog = Dialog(theView, {
            title = "Settings",
            width = 300,
            height = 190,
            x = 50,  
            y = 50,  

            elements = {
                -- Decimals Toggle
                { type = "TextLabel", x = labelCol1X, y = 40, text = "Decimals:" },
                { type = "TextButton", x = valueCol1X, y = 38, text = (_G.autoDecimal and "ON" or "OFF"),
                  width = btnW, height = btnH, name = "decimalsBtn",
                  command = function(dlg, btn)
                      _G.autoDecimal = not _G.autoDecimal
                      btn.text = (_G.autoDecimal and "ON" or "OFF")
                      var.store("nLuaCAS_decimals_pref", _G.autoDecimal and 1 or 0)
                      platform.window:invalidate()
                  end },

                -- Complex Mode Toggle
                { type = "TextLabel", x = labelCol1X, y = 40 + lineHeight, text = "Complex:" },
                { type = "TextButton", x = valueCol1X, y = 40 + lineHeight - 2, text = (_G.showComplex and "ON" or "OFF"),
                  width = btnW, height = btnH, name = "complexBtn",
                  command = function(dlg, btn)
                      _G.showComplex = not _G.showComplex
                      btn.text = (_G.showComplex and "ON" or "OFF")
                      var.store("nLuaCAS_complex_pref", _G.showComplex and 1 or 0)
                      platform.window:invalidate()
                  end },

                -- Constants Toggle
                { type = "TextLabel", x = labelCol1X, y = 40 + 2 * lineHeight, text = "Constants:" },
                { type = "TextButton", x = valueCol1X, y = 40 + 2 * lineHeight - 2, text = (not var.recall("constants_off") and "ON" or "OFF"),
                  width = btnW, height = btnH, name = "constantsBtn",
                  command = function(dlg, btn)
                      local new_off = not var.recall("constants_off")
                      var.store("constants_off", new_off)
                      btn.text = (not new_off and "ON" or "OFF")
                      platform.window:invalidate()
                  end },

                -- Category Selector
                { type = "TextLabel", x = labelCol1X, y = 40 + 3 * lineHeight, text = "Category:" },
                { type = "TextButton", x = valueCol1X, y = 40 + 3 * lineHeight - 2, text = _G.gui.get_current_constant_category(),
                  width = 90, height = btnH, name = "categoryBtn",
                  command = function(dlg, btn)
                      local categories = get_constant_categories()
                      local currentCategory = _G.gui.get_current_constant_category()
                      local idx = 1
                      for i, v in ipairs(categories) do
                          if v == currentCategory then idx = i end
                      end
                      local selected = categories[(idx % #categories) + 1]

                      _G.currentConstCategory = selected
                      _G.current_constant_category = selected

                      var.store("current_constant_category", selected)
                      btn.text = selected

                      platform.window:invalidate()
                  end },

                -- Dismiss Button for the dialog
                -- Position it relative to the new dialog height
                { type = "TextButton", x = 300 - 70, y = 190 - 30, text = "Dismiss", -- Y-position adjusted for new height
                  closesDialog = true,
                  command = function(dlg, btn)
                  end }
            },
            onClose = function(dlg, result)
                _G.showSettingsModal = false
                platform.window:invalidate()
                if fctEditor and fctEditor.editor then -- Add nil check for robustness
                    fctEditor.editor:setVisible(true)
                end
            end
        })
        theView:add(_G.settingsDialog)
        _G.settingsDialog:activate()
    end
    _G.settingsDialog:paint(gc, true)
end


    if _G.showHelpModal then
        if not _G.helpDialog then
            if fctEditor and fctEditor.editor then -- Add nil check for robustness
                fctEditor.editor:setVisible(false) -- HIDE EDITOR WHEN DIALOG OPENS
            end
            _G.helpDialog = Dialog(theView, {
                title = "CAS Help",
                width = 300,
                height = 200,
                elements = {
                    { type = "TextLabel", x = 10, y = 40, text = "Use Ctrl+MENU to open the menu." },
                    { type = "TextLabel", x = 10, y = 56, text = "Arrow keys or touch/click to navigate." },
                    { type = "TextLabel", x = 10, y = 72, text = "Select operations to insert into input." },
                    { type = "TextLabel", x = 10, y = 88, text = "Press Enter to compute." },
                    { type = "TextLabel", x = 10, y = 104, text = "Supports expand, factor, simplify," },
                    { type = "TextLabel", x = 10, y = 120, text = "differentiate, integrate, solve, abs," },
                    { type = "TextLabel", x = 10, y = 136, text = "factorial, empty matrix, series" },
                    { type = "TextButton", x = 300 - 70, y = 200 - 30, text = "Close",
                      closesDialog = true,
                      command = function(dlg, btn) end }
                },
                onClose = function(dlg, result)
                _G.showHelpModal = false
                    platform.window:invalidate()
                    if fctEditor and fctEditor.editor then -- SHOW EDITOR WHEN DIALOG CLOSES
                        fctEditor.editor:setVisible(true)
                    end
                end
            })
            theView:add(_G.helpDialog)
            _G.helpDialog:activate()
        end
        _G.helpDialog:paint(gc, true)
    end
    

   -- Handle the Startup Hint Dialog
if var and var.recall and var.recall("hide_startup_hint") ~= 1 and _G.showStartupHint then
    if not _G.startupHintDialog then
        if fctEditor and fctEditor.editor then
            fctEditor.editor:setVisible(false)
        end
        _G.startupHintDialog = Dialog(theView, {
            title = "Tip",
            width = 280,
            height = 160,
            elements = {
                { type = "TextLabel", x = 20, y = 40, text = "Press Ctrl+MENU to open the menu." },
                { type = "TextLabel", x = 20, y = 56, text = "You can access all features from there." },
                { type = "CheckBox", x = 20, y = 90, text = "Don't show this tip again", checked = false, name = "dontShow",
                  onAction = function(self)
                      self.checked = not self.checked
                      platform.window:invalidate()
                  end
                },
                { type = "TextButton", x = 280 - 70, y = 160 - 30, text = "Dismiss",
                  closesDialog = true,
                  command = function(dlg, btn) end }
            },
            onClose = function(dlg, result)
                if dlg.namedWidgets.dontShow and dlg.namedWidgets.dontShow.checked then
                    if var and var.store then
                        var.store("hide_startup_hint", 1)
                    end
                end
                if fctEditor and fctEditor.editor then
                    fctEditor.editor:setVisible(true)
                end
                _G.showStartupHint = false
                platform.window:invalidate()
            end
        })
        theView:add(_G.startupHintDialog)
        _G.startupHintDialog:activate()
    end
    -- --- START OF CHANGE ---
    -- Move the paint call OUTSIDE the 'if not _G.startupHintDialog then' block
    if _G.startupHintDialog and _G.startupHintDialog.visible then -- Ensure it exists and is visible before painting
        _G.startupHintDialog:paint(gc, true)
    end
    -- --- END OF CHANGE ---
end
end

font = "sansserif"
style = "r"
fsize = 12

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

    -- Set dark/light mode colors for both new MathEditors (mee, mer) consistently
    local bg = _G.darkMode and {30, 30, 30} or {255, 255, 255}
    local text = _G.darkMode and {255, 255, 255} or {0, 0, 0}
    local border = _G.darkMode and {100, 100, 100} or {0, 0, 0}
    for _, editor in ipairs({mee.editor, mer.editor}) do
        if editor.setBackgroundColor then
            editor:setBackgroundColor(table.unpack(bg))
        end
        if editor.setTextColor then
            editor:setTextColor(table.unpack(text))
        end
        if editor.setBorderColor then
            editor:setBorderColor(table.unpack(border))
        end
        if editor.setOpaque then
            editor:setOpaque(true)
        end
    end

	reposME()

-- Any unhandled errors will cause LuaCAS Engine status to go NONE (red)
end
-- Make var globally accessible for parser/physics.lua
_G.var = var

function on.construction()
  setupLaunchAnimation()
  toolpalette.register(myToolPaletteMenuStructure)
end
function on.timer()
    if showLaunchAnim then
        platform.window:invalidate()
    else
        timer.stop()
    end
end
_G.gui = _G.gui or {}

function _G.gui.get_current_constant_category()
    -- Priority: in-memory global -> storage -> default
    if _G.current_constant_category and type(_G.current_constant_category) == "string" then
        return _G.current_constant_category
    end
    local cat = var.recall and var.recall("current_constant_category")
    if cat and type(cat) == "string" then
        _G.current_constant_category = cat
        return cat
    end
    return "fundamental"
end