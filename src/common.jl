
"Thrown upon detection of user data that is not supported."
struct DataFormatError <: Exception
    msg::AbstractString
end

struct InvalidRange <: Exception
    msg::AbstractString
end

struct InvalidValue <: Exception
    msg::AbstractString
end
