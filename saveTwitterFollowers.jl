using OAuth
using Requests
using DBI
using PostgreSQL

#Must define Twitter OAuth Keys and user screen name. Example:

# consumerKey = "W123..."
# consumerSecret = "X456..."
# accessToken =  "Y789..."
# accessTokenSecret = "Z321..."
# screenName = "myScreenName"

println("Insert Twitter Settings file")
twSettingsFile = chomp(readline(STDIN))
include(twSettingsFile)

# Must define the database name, table to insert into, the host and ports used,
# and a valid user password. Example:

# host = "localhost"
# port = 5432
# database = "my_database"
# insertingTable = "my_followers"
# username = "user"
# password = "pswd"

# Fields in the table must be:
#  (id BIGINT,
#  follower JSON)

println("Insert database Settings file")
dbSettingsFile = chomp(readline(STDIN))
include(dbSettingsFile)

idsEndpoint = "https://api.twitter.com/1.1/followers/ids.json"
usersEndpoint = "https://api.twitter.com/1.1/users/lookup.json"

cursor = -1

usersCount = 0

count = 100

while(cursor != 0)

    options = Dict{Any, Any}("cursor" => "$cursor",
                             "screen_name" => screenName,
			     "count" => "$count")

    response = oauth_request_resource(idsEndpoint, "GET", options,
                                      consumerKey, consumerSecret,
                                      accessToken, accessTokenSecret)

    if response.status == 200
        usersListJSON = JSON.parse(bytestring(response.data))
        remaining = response.headers["x-rate-limit-remaining"]
        remaining = parse(Int, remaining)
        refreshTime = response.headers["x-rate-limit-reset"]
        refreshTime = parse(Int, refreshTime)
    else
        usersListJSON = bytestring(response.data)
        print("Something went wrong: $usersListJSON\n")
        break
    end

    usersList = string(usersListJSON["ids"])
    usersList = usersList[5:(end-1)]
    
    options = Dict{Any, Any}("user_id" => usersList)

    response = oauth_request_resource(usersEndpoint, "GET", options,
                                      consumerKey, consumerSecret,
                                      accessToken, accessTokenSecret)

    if response.status == 200
        users = JSON.parse(bytestring(response.data))
        remainingUsers = response.headers["x-rate-limit-remaining"]
        remainingUsers = parse(Int, remainingUsers)
        refreshTimeUsers = response.headers["x-rate-limit-reset"]
        refreshTimeUsers = parse(Int, refreshTimeUsers)
    else
        users = bytestring(response.data)
        print("Something went wrong: $users \n")
        break
    end

    conn = connect(Postgres, host, username, password, database, port)

    for user in users
        if(user["screen_name"] == screenName)
            continue
	else
            usersCount += 1
            insertStatement =  "INSERT INTO $insertingTable (id, follower)"
            insertStatement *= " VALUES ($(user["id"]), '$(JSON.json(user))')"
            statement = prepare(conn, insertStatement)
            execute(statement)
            finish(statement)
        end
    end

    print("Done $usersCount users.\n")
    
    cursor = usersListJSON["next_cursor"]
        
    if((remaining == 0) || (remainingUsers == 0))
        sleepingTime = max(refreshTime, refreshTimeUsers) - time()
        sleepingTime += 60
        print("Sleeping for $(sleepingTime / 60) minutes.\n")
        sleep(sleepingTime)
        print("Done Sleeping.\n")
    end

end

println("Done saving users!")
