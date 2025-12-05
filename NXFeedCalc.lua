AnimalFoodCalculator = {}
AnimalFoodCalculator.name = g_currentModName or "AnimalFoodCalculator"
AnimalFoodCalculator.data = {}
AnimalFoodCalculator.daysPerPeriod = nil

AnimalFoodCalculator.isEAS =
    g_modManager ~= nil and g_modManager:getModByName("FS25_EnhancedAnimalSystem") ~= nil

local function getClustersFromObject(obj)
    if not obj then return nil end

    local function tryGetClusters(o)
        if type(o.getClusters) == "function" then
            local ok, res = pcall(o.getClusters, o)
            if ok and type(res) == "table" then return res end
        end
        if type(o.clusters) == "table" then return o.clusters end
        return nil
    end

    local clusters = tryGetClusters(obj)
    if clusters then return clusters end
    if obj.spec_husbandryAnimals then
        clusters = tryGetClusters(obj.spec_husbandryAnimals)
        if clusters then return clusters end
    end
    if obj.owningPlaceable and obj.owningPlaceable.spec_husbandryAnimals then
        clusters = tryGetClusters(obj.owningPlaceable.spec_husbandryAnimals)
        if clusters then return clusters end
    end
    if type(obj.getModuleByName) == "function" then
        local ok, mod = pcall(obj.getModuleByName, obj, "husbandryAnimals")
        if ok and mod then
            clusters = tryGetClusters(mod)
            if clusters then return clusters end
        end
    end
    return nil
end

local function getHusbandryKey(h)
    if h and h.owningPlaceable and h.owningPlaceable.id then
        return "placeable_" .. tostring(h.owningPlaceable.id)
    end
    return tostring(h)
end

local function getCurrentFood(h)
    if not h then return 0 end
    local total = 0
    local target = h.owningPlaceable or h

    local spec = target.spec_husbandryFood
    if spec and spec.fillLevels then
        for fillTypeIndex, fillLevel in pairs(spec.fillLevels) do
            if fillLevel and fillLevel > 0 then
                total = total + fillLevel
            end
        end
    end

    if total == 0 then
        if target.storage and target.storage.fillLevels then
            for fillTypeIndex, fillLevel in pairs(target.storage.fillLevels) do
                if fillLevel > 0 then
                    total = total + fillLevel
                end
            end
        end
    end

    if total == 0 then
        if target.foodStorage then
            if type(target.foodStorage.fillLevel) == "number" and target.foodStorage.fillLevel > 0 then
                total = total + target.foodStorage.fillLevel
            end
            if target.foodStorage.fillLevels then
                for idx, lvl in pairs(target.foodStorage.fillLevels) do
                    if lvl > 0 then
                        total = total + lvl
                    end
                end
            end
        end
    end

    if total == 0 then
        if target.spec_husbandryStorage and target.spec_husbandryStorage.fillLevels then
            for idx, lvl in pairs(target.spec_husbandryStorage.fillLevels) do
                if lvl > 0 then
                    total = total + lvl
                end
            end
        end
    end

    return total
end

function AnimalFoodCalculator:calcFoodByAge(cluster, extraMonths)
    if not cluster or cluster.subTypeIndex == nil then return 0 end
    if not g_currentMission or not g_currentMission.animalSystem or not g_currentMission.animalSystem.subTypes then return 0 end

    local subType = g_currentMission.animalSystem.subTypes[cluster.subTypeIndex]
    if not subType or not subType.input or not subType.input["food"] then return 0 end

    local idx = (cluster.age or 0) + (extraMonths or 0)
    if idx < 0 then idx = 0 end

    local foodInput = subType.input["food"]
    local baseVal = 0
    if type(foodInput.get) == "function" then
        baseVal = foodInput:get(idx)
    elseif type(foodInput[idx]) == "number" then
        baseVal = foodInput[idx]
    end

    if AnimalFoodCalculator.isEAS and cluster.lactating then
        baseVal = baseVal * (cluster.lactationFactor or 1)
    end

    return baseVal
end

local function getDaysPerMonth()
    if g_currentMission and g_currentMission.missionInfo then
        if g_currentMission.missionInfo.plannedDaysPerPeriod ~= nil then
            return g_currentMission.missionInfo.plannedDaysPerPeriod
        elseif g_currentMission.missionInfo.daysPerPeriod ~= nil then
            return g_currentMission.missionInfo.daysPerPeriod
        end
    end
    return 1
end

function AnimalFoodCalculator:calcFoodPerCluster(cluster)
    if not cluster or cluster.numAnimals == nil then return 0, 0, 1 end

    local num = cluster.numAnimals
    local perAnimalPerDay = self:calcFoodByAge(cluster, 0)

    local daily = perAnimalPerDay * num
    local dpm = getDaysPerMonth()
    local monthly = daily * dpm

    return daily, monthly, dpm
end

function AnimalFoodCalculator:onAnimalsChanged(h)
    if not h then return end
    local clusters = getClustersFromObject(h)
    if not clusters then return end

    local totalDaily, totalMonthly = 0, 0
    local dpm = getDaysPerMonth()

    for _, c in ipairs(clusters) do
        local d, m = self:calcFoodPerCluster(c)
        totalDaily = totalDaily + (d or 0)
        totalMonthly = totalMonthly + (m or 0)
    end

    h.nxfcDaily = totalDaily
    h.nxfcMonthly = totalMonthly

    local key = getHusbandryKey(h)
    if key then
        self.data[key] = { daily = totalDaily, monthly = totalMonthly, daysPerMonth = dpm }
    end
end

function AnimalFoodCalculator:update(dt)
    local now = getDaysPerMonth()
    if now ~= self.daysPerPeriod then
        self.daysPerPeriod = now

        if g_currentMission and g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables then
            for _, place in pairs(g_currentMission.placeableSystem.placeables) do
                if place.spec_husbandryAnimals then
                    self:onAnimalsChanged(place.spec_husbandryAnimals)
                end
            end
        end
    end
end

local function NXFC_GUI(self, husbandry, ...)
    if not husbandry then
        husbandry = self.husbandry or self.selectedHusbandry or self.animalHusbandry or self.currentHusbandry
    end
    if not husbandry then
        if type(self.getDisplayedHusbandry) == "function" then
            local ok, h = pcall(self.getDisplayedHusbandry, self)
            if ok and h then husbandry = h end
        end
    end
    if not husbandry then return end

    AnimalFoodCalculator:onAnimalsChanged(husbandry)

    local clusters = getClustersFromObject(husbandry)
    if not clusters then return end

    local totalDaily, totalMonthly = 0, 0
    local dpm = getDaysPerMonth()

    for _, c in ipairs(clusters) do
        local d, m = AnimalFoodCalculator:calcFoodPerCluster(c)
        totalDaily = totalDaily + (d or 0)
        totalMonthly = totalMonthly + (m or 0)
    end

    local currentFood = getCurrentFood(husbandry)
    local daysRemaining = (totalDaily > 0) and (currentFood / totalDaily) or 0

    local statusString = ""
    if daysRemaining >= dpm then
        -- *** FIXED: Rounded month display to 1 decimal place ***
        local months = daysRemaining / dpm
        statusString = string.format("%.1fm", months)

    elseif daysRemaining > 0 then
        statusString = string.format("%.1fd", daysRemaining)
    else
        statusString = (currentFood > 0) and "<0.1d" or "Empty"
    end

    local fmt = "%.0fl Monthly / %.0fl (%s) Remaining"
    if g_i18n and type(g_i18n.getText) == "function" then
        local ok, txt = pcall(g_i18n.getText, g_i18n, "nxfc_gui_format")
        if ok and txt and txt ~= "" then fmt = txt end
    end

    local nxfcText = string.format(fmt, totalMonthly, currentFood, statusString or "")

    if self.foodRowTotalValue and type(self.foodRowTotalValue.setText) == "function" then
        pcall(self.foodRowTotalValue.setText, self.foodRowTotalValue, nxfcText)
    end
    if self.foodRowValue and type(self.foodRowValue.setText) == "function" then
        pcall(self.foodRowValue.setText, self.foodRowValue, "")
    end
    if self.foodRowFillLevelValue and type(self.foodRowFillLevelValue.setText) == "function" then
        pcall(self.foodRowFillLevelValue.setText, self.foodRowFillLevelValue, "")
    end
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
    AnimalFoodCalculator.daysPerPeriod = getDaysPerMonth()

    if g_messageCenter then
        g_messageCenter:subscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, function(h) AnimalFoodCalculator:onAnimalsChanged(h) end)
    end

    if g_currentMission then
        table.insert(g_currentMission.updateables, AnimalFoodCalculator)
    end

    if InGameMenuAnimalsFrame and type(InGameMenuAnimalsFrame.updateHusbandryDisplay) == "function" then
        InGameMenuAnimalsFrame.updateHusbandryDisplay =
            Utils.appendedFunction(InGameMenuAnimalsFrame.updateHusbandryDisplay, NXFC_GUI)
    end
end)

return AnimalFoodCalculator