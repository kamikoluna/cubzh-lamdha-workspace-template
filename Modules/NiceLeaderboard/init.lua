--- A module to create a uikit node that nicely displays a leaderboard.
--- (using Leaderboard API data)
---@code
--- niceLeaderboard = require("github.com/aduermael/modzh/niceleaderboard")
--- l = niceLeaderboard()
--- l.Width = 400
--- l.Height = 400
--- l.pos = { Screen.Width * 0.5 - l.Width * 0.5, Screen.Height * 0.5 - l.Height * 0.5 }

local mod = {}

local MIN_HEIGHT = 100
local MIN_WIDTH = 100
local AVATAR_SIZE = 50

local ui = require("uikit")
local theme = require("uitheme").current
local conf = require("config")
local api = require("api")
local uiAvatar = require("ui_avatar")

local defaultConfig = {
	leaderboardName = "default",
	-- function(response) that can return a string to be displayed below score
	-- response is of this form { score = 1234, updated = OSTime, value = AnyLuaValue }
	extraLine = nil,
}

setmetatable(mod, {
	__call = function(_, config)
		if Client.BuildNumber < 186 then
			error("niceLeaderboard can only be used from Cubzh 0.1.8", 2)
		end
		local ok, err = pcall(function()
			config = conf:merge(defaultConfig, config, {
				acceptTypes = {
					leaderboardName = { "string" },
					extraLine = { "function" },
				},
			})
		end)
		if not ok then
			error("niceLeaderboard(config) - config error: " .. err, 2)
		end

		local status = "loading"
		local leaderboard

		local requests = {}
		local nbUserInfoToFetch = 0
		local pendingUserInfoRequestScore = {} -- requests to retrieve user info

		local function cancelRequests()
			for _, r in ipairs(requests) do
				r:Cancel()
			end
			requests = {}
			nbUserInfoToFetch = 0
			pendingUserInfoRequestScore = {}
		end

		-- cache for users (usernames, avatars)
		local users = {}
		local friendScores = {}

		local recycledCells = {}

		local cellSelector = ui:frameScrollCellSelector()
		cellSelector:setParent(nil)

		local scroll

		local cellParentDidResize = function(self)
			local parent = scroll
			if parent == nil then
				return
			end
			self.Width = parent.Width - 4

			local availableWidth = self.Width - theme.padding * 3 - AVATAR_SIZE

			self.username.object.Scale = 1
			local scale = math.min(1, availableWidth / self.username.Width)
			self.username.object.Scale = scale

			self.score.object.Scale = 1
			scale = math.min(1, availableWidth / self.score.Width)
			self.score.object.Scale = scale

			self.Height = self.score.Height + self.username.Height + theme.padding * 2
			if self.extraLine:isVisible() then
				self.Height = self.Height + self.extraLine.Height
				self.extraLine.object.Scale = 1
				scale = math.min(1, availableWidth / self.extraLine.Width)
				self.extraLine.object.Scale = scale
			end

			self.username.pos = {
				theme.padding * 2 + AVATAR_SIZE + availableWidth * 0.5 - self.username.Width * 0.5,
				self.Height - self.username.Height - theme.padding,
			}
			self.score.pos = {
				theme.padding * 2 + AVATAR_SIZE + availableWidth * 0.5 - self.score.Width * 0.5,
				self.username.pos.Y - self.score.Height,
			}
			self.extraLine.pos = {
				theme.padding * 2 + AVATAR_SIZE + availableWidth * 0.5 - self.extraLine.Width * 0.5,
				self.score.pos.Y - self.extraLine.Height,
			}

			self.avatar.pos = {
				theme.padding,
				self.Height * 0.5 - AVATAR_SIZE * 0.5 + theme.paddingTiny,
			}

			if self.userID == Player.UserID then
				cellSelector:setParent(self)
				cellSelector.Width = self.Width
				cellSelector.Height = self.Height
			end
		end

		local function formatNumber(num)
			local formatted = tostring(num)
			local k
			while true do
				formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
				if k == 0 then
					break
				end
			end
			return formatted
		end

		local messageCell

		local functions = {}

		local loadCell = function(index)
			if status == "scores" then
				if index <= #friendScores then
					local cell = table.remove(recycledCells)
					if cell == nil then
						cell = ui:frameScrollCell()

						cell.username = ui:createText("", { color = Color.White })
						cell.username:setParent(cell)

						cell.score = ui:createText("", { color = Color(200, 200, 200) })
						cell.score:setParent(cell)

						cell.extraLine = ui:createText("", { color = Color(100, 100, 100), size = "small" })
						cell.extraLine:setParent(cell)

						cell.avatar = uiAvatar:getHeadAndShoulders({
							-- usernameOrId = score.userID,
						})
						cell.avatar:setParent(cell)
						cell.avatar.Width = AVATAR_SIZE
						cell.avatar.Height = AVATAR_SIZE

						cell.parentDidResize = cellParentDidResize
						cell.onPress = function(_)
							cell:getQuad().Color = Color(220, 220, 220)
							Client:HapticFeedback()
						end

						cell.onRelease = function(self)
							if self.userID ~= nil and self.username.Text ~= nil then
								Menu:ShowProfile({
									id = self.userID,
									username = self.username.Text,
								})
							end
							cell:getQuad().Color = Color.White
						end

						cell.onCancel = function(_)
							cell:getQuad().Color = Color.White
						end
					end

					local score = friendScores[index]

					cell.userID = score.userID
					cell.username.Text = score.user.username
					cell.score.Text = formatNumber(score.score)
					cell.avatar:load({ usernameOrId = score.userID })

					cell:getQuad().Color = Color.White

					if config.extraLine ~= nil then
						cell.extraLine.Text = config.extraLine(score)
						cell.extraLine:show()
					else
						cell.extraLine:hide()
					end

					cell:parentDidResize()

					return cell
				end
			elseif status == "no_scores" or status == "error" then
				if index == 1 then
					if messageCell == nil then
						messageCell = ui:frame()

						messageCell.label = ui:createText("This is a test", { color = Color.White, size = "small" })
						messageCell.label:setParent(messageCell)

						messageCell.btn = ui:buttonNeutral({ content = "Test", textSize = "small" })
						messageCell.btn:setParent(messageCell)

						messageCell.parentDidResize = function(self)
							local parent = scroll
							if parent == nil then
								return
							end
							self.Width = parent.Width - 4

							messageCell.label.object.MaxWidth = self.Width - theme.padding * 2

							self.Height = math.max(
								parent.Height - 4,
								messageCell.label.Height + self.btn.Height + theme.padding * 3
							)

							local h = self.btn.Height + theme.padding + self.label.Height
							local y = self.Height * 0.5 - h * 0.5

							self.btn.pos = {
								self.Width * 0.5 - self.btn.Width * 0.5,
								y,
							}
							self.label.pos = {
								self.Width * 0.5 - self.label.Width * 0.5,
								self.btn.pos.Y + self.btn.Height + theme.padding,
							}
						end
					end

					if status == "no_scores" then
						messageCell.label.Text = "No scores to display yet!"
						messageCell.btn.Text = "👥 Add Friends"
						messageCell.btn.onRelease = function()
							Menu:ShowFriends()
						end
					else
						messageCell.label.Text = "❌ Error: couldn't load scores."
						messageCell.btn.Text = "Retry"
						messageCell.btn.onRelease = function()
							functions.refresh()
						end
					end

					messageCell:parentDidResize()

					return messageCell
				end
			end
		end

		local unloadCell = function(_, cell)
			cell:setParent(nil)
			if cell ~= messageCell then
				table.insert(recycledCells, cell)
			end
		end

		local node = ui:frameTextBackground()

		scroll = ui:scroll({
			backgroundColor = theme.buttonTextColor,
			padding = 2,
			cellPadding = 2,
			direction = "down",
			loadCell = loadCell,
			unloadCell = unloadCell,
			-- userdata = dataFetcher,
			-- centerContent = true,
		})
		scroll:setParent(node)
		scroll.pos = {
			theme.padding,
			theme.padding,
		}
		scroll:hide()

		local loading = require("ui_loading_animation"):create({ ui = ui })
		loading.parentDidResize = function(self)
			local parent = self.parent
			loading.pos = {
				parent.Width * 0.5 - loading.Width * 0.5,
				parent.Height * 0.5 - loading.Height * 0.5,
			}
		end
		loading:setParent(node)

		node.parentDidResizeSystem = function(self)
			self.Width = math.max(MIN_WIDTH, self.Width)
			self.Height = math.max(MIN_HEIGHT, self.Height)

			scroll.Width = self.Width - theme.padding * 2
			scroll.Height = self.Height - theme.padding * 2
		end
		node:parentDidResizeSystem()

		local localUserScrollIndex

		local function refresh()
			if nbUserInfoToFetch > 0 then
				return
			end

			loading:hide()
			scroll:flush()
			scroll:refresh()
			scroll:show()

			if localUserScrollIndex ~= nil then
				scroll:setScrollIndexVisible(localUserScrollIndex)
			end

			node:parentDidResizeSystem()
			if node.parentDidResize then
				node:parentDidResize()
			end
		end
		functions.refresh = refresh

		local function displayScores(scores)
			status = "scores"
			nbUserInfoToFetch = #scores
			localUserScrollIndex = nil

			friendScores = scores

			for i, s in ipairs(friendScores) do
				if s.userID == Player.UserID then
					localUserScrollIndex = i
				end

				if users[s.userID] ~= nil then
					s.user = users[s.userID]
					nbUserInfoToFetch = nbUserInfoToFetch - 1
					refresh()
				else
					if pendingUserInfoRequestScore[s.userID] == nil then
						local req = api:getUserInfo(s.userID, function(userInfo, err)
							if err ~= nil then
								pendingUserInfoRequestScore[s.userID] = nil
								return
							end
							pendingUserInfoRequestScore[s.userID] = nil
							users[s.userID] = {
								username = userInfo.username,
							}
							s.user = users[s.userID]
							nbUserInfoToFetch = nbUserInfoToFetch - 1
							refresh()
						end, {
							"username",
						})
						pendingUserInfoRequestScore[s.userID] = s
						table.insert(requests, req)
					end
				end
			end
		end

		leaderboard = Leaderboard(config.leaderboardName)

		local function load()
			status = "loading"
			cancelRequests()
			friendScores = {}

			cellSelector:setParent(nil)
			scroll:hide()
			scroll:flush()
			loading:show()

			-- fetch best scores first
			-- load neighbors only if user not in top 5
			local req = leaderboard:get({
				mode = "best",
				friends = true,
				limit = 10,
				callback = function(scores, err)
					if err ~= nil then
						if string.find(err, "404") then
							status = "no_scores"
						else
							status = "error"
						end
						refresh()
						return
					end

					for _, s in ipairs(scores) do
						if s.userID == Player.UserID then
							-- found user in top, display scores!
							displayScores(scores)
							return
						end
					end

					-- local user not in top, get neighbors instead
					cancelRequests()
					local req = leaderboard:get({
						mode = "neighbors",
						friends = true,
						limit = 10,
						callback = function(scores, err)
							if err ~= nil then
								if string.find(err, "404") then
									status = "no_scores"
								else
									status = "error"
								end
								refresh()
								return
							end
							displayScores(scores)
						end,
					})
					table.insert(requests, req)
				end,
			})
			table.insert(requests, req)
		end

		node.reload = load
		load()

		return node
	end,
})

return mod
