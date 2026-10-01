--!strict
-- The game's Directors (Operators): the solo creator plus Config.AdminUserIds. They wear the red
-- nameplate and aura, stand outside the rankings and get their own statue by the egg.

local Config = require(script.Parent.Config)

local Operators = {}

function Operators.is(userId: number): boolean
	return (userId == game.CreatorId and game.CreatorType == Enum.CreatorType.User) or table.find(Config.AdminUserIds, userId) ~= nil
end

-- The community group (Config.GroupId, or the group that owns the experience); 0 when none.
function Operators.groupId(): number
	if Config.GroupId > 0 then
		return Config.GroupId
	end
	return if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
end

-- Every Director's UserId (the creator first when the experience is user-owned).
function Operators.list(): { number }
	local list = table.clone(Config.AdminUserIds)
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 and not table.find(list, game.CreatorId) then
		table.insert(list, 1, game.CreatorId)
	end
	return list
end

return Operators
