-- Second parameter of RegisterMod() is the API version
local mod = RegisterMod("The Unforgiving", 1) 




-- Renders text to screen during game runtime, abstracting RenderText() method
local function DebugString(string)
    Isaac.RenderText(string, 50, 30, 1, 1 ,1 ,255)
end

-- Inverts, if outside of bounds
local function Bounce(inverse, buffer, entity) 
    local room = Game():GetLevel():GetCurrentRoom()
    local pos = entity.Position
    -- Y coordinates are written with down being being positive
    local bottomRight = room:GetBottomRightPos() 
    local topLeft = room:GetTopLeftPos()  

    -- Adding an inner buffer for the walls
    bottomRight.X = bottomRight.X - buffer
    bottomRight.Y = bottomRight.Y - buffer
    topLeft.X = topLeft.X + buffer
    topLeft.Y = topLeft.Y + buffer

    if pos.X > bottomRight.X then
        inverse.X = true
    elseif pos.X < topLeft.X then
        inverse.X = false
    end
    if pos.Y < topLeft.Y then
        inverse.Y = true
    elseif pos.Y > bottomRight.Y then
        inverse.Y = false
    end

    return inverse.X, inverse.Y 
end




-- Defining constants
local BOSS_ID = Isaac.GetEntityTypeByName("The Unforgiving")
local SPIKES_VARIANT_ID = Isaac.GetEntityVariantByName("Custom Spikes")
local BASE_SPEED = 3
-- This is the smallest buffer that acts reliably
local ENTITY_BUFFER = 21  


-- Enumerations for actions
local actions = {   
    APPEAR =        1,
    IDLE =          2,
    CRISS_CROSS =   3,
    DEATH =         4,
    DEBUG_ACTION =  5
}

local markovChain = {
    [actions.APPEAR] =          {0.0, 1.0, 0.0, 0.0, 0.0},
    [actions.IDLE] =            {0.0, 0.5, 0.3, 0.0, 0.2},
    [actions.CRISS_CROSS] =     {0.0, 0.6, 0.0, 0.0, 0.4},
    [actions.DEATH] =           {0.0, 0.0, 0.0, 0.0, 0.0}, 
    -- To prove it can move between two actions reliably
    [actions.DEBUG_ACTION] =    {0.0, 0.8, 0.2, 0.0 ,0.0} 
}

-- Defining empty locals to be used later, so they are in the correct scope
local actionTable = {}
local childEntityTables = {
    spikesTable = {},
    tearsTable = {},
    brimsTable = {}
}
local currentAction = nil
local stateFrame = 0
local currentActionFinished = nil
local targetVelocity = nil
local targetVector = nil
local speed = nil
local tearsRemaining
local entityInverse = {
    X = false,
    Y = false
}
-- tearInverse needs to be added as entity data, may be time to make this change for all variables here
-- Entity data will always be in correct scope as it is retrieved




-- Definitions of all actions
local function MakeActions()

    -- Appear action
    actionTable[actions.APPEAR] = (function(entity)
        if (stateFrame == 0) then
            -- Second parameter of Play() says whether to force the animation
            entity:GetSprite():Play("Appear", false) 
            targetVector = Vector(0, 0)
            speed = 0 * BASE_SPEED
        end
        
        if entity:GetSprite():IsEventTriggered("Finish") or entity:GetSprite():IsFinished("Appear") then
            currentActionFinished = true
        end
    end)

    -- Idle action
    actionTable[actions.IDLE] = (function(entity)
        if (stateFrame == 0) then
            entity:GetSprite():Play("Idle", false)
        end
        targetVector = Vector(1, -1)
        speed = 1 * BASE_SPEED
        if entity:GetSprite():IsEventTriggered("Finish") then
            currentActionFinished = true
        end
    end)

    -- Criss cross tear streams attack
    actionTable[actions.CRISS_CROSS] = (function(entity)
        if (stateFrame == 0) then
            entity:GetSprite():Play("Criss Cross", false)
            tearsRemaining = 50
            
        end
        targetVector = Vector(1, -1)
        speed = 0.5 * BASE_SPEED

        DebugString("Criss Cross")
        local room = Game():GetLevel():GetCurrentRoom()
        local center = room:GetCenterPos()
        local topLeft = room:GetTopLeftPos() 
        local startPosition = Vector(topLeft.X, center.Y)
        local tearVector = Vector.FromAngle(60.0)
        local tearSpeed = 7
        local interval = 2

        local CONTINUUM_FLAG = TearFlags.TEAR_CONTINUUM

        if (stateFrame % interval == 0) and (tearsRemaining >= 1) then
            local place = #(childEntityTables.tearsTable) + 1
            local velocity = tearVector * tearSpeed
            local tear = Isaac.Spawn(EntityType.ENTITY_TEAR, TearVariant.LOST_CONTACT, 0, startPosition, velocity, entity)
            tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY

            -- tear.TearFlags = CONTINUUM_FLAG

            childEntityTables.tearsTable[place] = tear


            -- Failing to add entity flags
            -- Tears range is too short
            -- Maybe override tear behaviour here or in Update()
            -- Can modify falling speed


            place = #(childEntityTables.tearsTable) + 1
            velocity.Y = -velocity.Y
            tear = Isaac.Spawn(EntityType.ENTITY_TEAR, TearVariant.DARK_MATTER, 0, startPosition, velocity, entity)
            tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY

            -- tear:AddEntityFlags(TearFlags.TEAR_CONTINUUM)

            childEntityTables.tearsTable[place] = tear
        end


        if entity:GetSprite():IsEventTriggered("Finish") then
            -- Why didn't IsFinished() work here?
            -- Finishes once, not second time
            tearsRemaining = 0
            currentActionFinished = true
        end
    end)

    -- Death action
    actionTable[actions.DEATH] = (function(entity) 
        entity:GetSprite():Play("Death", false)
        entity:PlaySound(SoundEffect.SOUND_DEATH_BURST_LARGE, 1, 0, false, 1)

        -- Cleanup, emptying tables and variables
        for _, entityTable in pairs(childEntityTables) do
            for i, entityObject in pairs(entityTable) do
                entityObject:Remove()
                entityTable[i] = nil
            end
        end

        entity:Kill()
        currentAction = nil
        -- One more is added when action leaves, this resets it to 0 for the next instance if necessary
        stateFrame = -1 
    end)

    -- Debug action, to prove correct movement between actions 
    actionTable[actions.DEBUG_ACTION] = (function(entity)
        if (stateFrame == 0) then
            entity:GetSprite():Play("Idle", false)
        end
        targetVector = Vector(1, -1)
        speed = 0.8 * BASE_SPEED
        DebugString("In debug action")
        if entity:GetSprite():IsEventTriggered("Finish") then
            currentActionFinished = true
        end
    end)
end

-- Calls the associated function from the table made in MakeActions()
local function RunAction(actionName, entity) 
    local actionFunc = actionTable[actionName]
    actionFunc(entity)
end

-- Modified code from a tutorial by Lytebringr on Youtube
local function MarkovTransition(state) 
    local roll = math.random()
    -- # of a table returns its size
    for i = 1, #markovChain do 
        roll = roll - markovChain[state][i]
        if (roll <= 0) then
            return i
        end
    end
    -- This is a safety net, the code shouldn't reach here, but should return a valid value in case it does
    print("Markov safety net reached")
    return actions.IDLE
end




local function Update(entity)
    -- Checks for entity death
    if entity:IsDead() then
        currentAction = actions.DEATH
    end

    -- Markov transition on action finished
    if (currentActionFinished) and (currentAction ~= actions.DEATH) then   
        currentAction = MarkovTransition(currentAction)
        stateFrame = 0
        currentActionFinished = false
    end
    RunAction(currentAction, entity)
    stateFrame = stateFrame + 1 

    -- Updating child entities, does nothing if doesn't exist
    -- I can't test this block right now as no child entities are spawned yet
    for _, entityTable in pairs(childEntityTables) do 
        for i, entityObject in pairs(entityTable) do
            if entityObject:IsDead() then
                entityObject:Remove()
                entityTable[i] = nil
            else
                entityObject:Update()
            end
        end
    end

    -- Velocity calculations
    entityInverse.X, entityInverse.Y = Bounce(entityInverse, ENTITY_BUFFER, entity)
    if entityInverse.X == true then
        targetVector.X = -targetVector.X
    end
    if entityInverse.Y == true then
        targetVector.Y = -targetVector.Y
    end

    -- Scale the unit vector for direction by the speed to move at
    targetVelocity = targetVector * speed 
    entity.Velocity = targetVelocity
    print("Entity speed:", entity.Velocity:Length())


    --[[ This snippet smooths out changes in velocity, could still be used in chase action
        velocity = (targetVelocity * 0.1) + (velocity * 0.9) 
        Could smooth out just the direction changes, by appliying this a little earlier on
    ]]--

    -- Flips the sprite if moving left
    entity.FlipX = false
    if (entity.Velocity.X < 0) then
        entity.FlipX = true
    end
end




-- The first parameter is provided as the function will look for itself, an underscore is used as a placeholder
local function CallbackHook(_, entity) 
    if (entity.Variant ~= SPIKES_VARIANT_ID) then
        -- Spikes are handled elsewhere, so do nothing here
        -- Check for first time looping
        if (currentAction == nil) then 
            MakeActions()
            currentAction = actions.APPEAR
            -- myBossCurrent = entity.GetDropRNG() -- 
            RunAction(currentAction, entity)
        else
            Update(entity)
        end
    else
        -- Set collides with player
        -- I want it to stop colliding while the player has immunity frames, but this may be too complex
        entity.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY
    end
end

-- When an entity with my boss ID updates, call CallbackHook
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, CallbackHook, BOSS_ID) 

local function TestRender()
    DebugString("Callback successful")
end

-- Uncomment line below for callback confirmation string (From prototype 1)
-- mod:AddCallback(ModCallbacks.MC_POST_RENDER, TestRender)