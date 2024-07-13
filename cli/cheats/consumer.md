# To list consumers

sequin consumer ls

# To add a new consumer

sequin consumer add [slug]

# To show consumer information

sequin consumer info [consumer-id]

# To receive messages for a consumer (default batch size is 1)

sequin consumer receive [consumer-id]

# To receive messages for a consumer without acknowledging them

sequin consumer receive [consumer-id] --no-ack

# To receive a batch of messages for a consumer

sequin consumer receive [consumer-id] --batch-size 10

# To peek at messages for a consumer (default shows last 10 messages)

sequin consumer peek [consumer-id]

# To peek only at pending messages for a consumer

sequin consumer peek [consumer-id] --pending

# To peek at the last N messages for a consumer

sequin consumer peek [consumer-id] --last 20

# To peek at the first N messages for a consumer

sequin consumer peek [consumer-id] --first 20

# To ack a message

sequin consumer ack [consumer-id] [ack-token]

# To nack a message

sequin consumer nack [consumer-id] [ack-token]

# To edit a consumer

sequin consumer edit [consumer-id]