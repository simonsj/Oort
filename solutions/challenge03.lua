function target_selector(k,c)
	return c:team() ~= team
end

my_ship = ships[class]

while true do
	local contacts = sensor_contacts({})
	local tid, t = pick(contacts, target_selector)
	if t ~= nil then
		local x, y = position()
		local vx, vy = velocity()
		local tx, ty = t:position()
		local tvx, tvy = t:velocity()
		local bv = 0
		local bt = 0
		
		if (my_ship.guns.main.bullet_velocity ~= nil) then
			bv = my_ship.guns.main.bullet_velocity
		end

		if (my_ship.guns.main.bullet_ttl ~= nil) then
			bt = my_ship.guns.main.bullet_ttl
		end

		local a = lead(x, y, tx, ty, vx, vy, tvx, tvy, bv, bt)
		if (a) then fire("main", a) end
	end
	yield()
end
