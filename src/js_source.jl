function iterate_interpolations(source::String)
    result = Union{Expr, JSString, Symbol}[]
    lastidx = 1; i = 1; lindex = lastindex(source)
    while true
        c = source[i]
        if c == '$'
            # add elements before $
            if !isempty(lastidx:(i - 1))
                push!(result, JSString(source[lastidx:(i - 1)]))
            end
            # parse the $ expression
            expr, i2 = Meta.parse(source, i + 1, greedy = false, raise = false)
            if i2 >= lindex && expr === nothing
                error("Invalid interpolation at index $(i)-$(lindex): $(source[i:lindex])")
            end
            i = i2
            push!(result, esc(expr))
            lastidx = i
            i > lindex && break
        else
            if i == lindex
                if !isempty(lastidx:lindex)
                    push!(result, JSString(source[lastidx:lindex]))
                end
                break
            end
            i = Base.nextind(source, i)
        end
    end
    return result
end

macro js_str(js_source)
    value_array = :([])
    append!(value_array.args, iterate_interpolations(js_source))
    return :(JSCode($value_array, $(string(__source__.file, ":", __source__.line))))
end

function Base.show(io::IO, jsc::JSCode)
    print_js_code(io, jsc, IdDict())
end

function print_js_code(io::IO, @nospecialize(object), objects::IdDict)
    id = get!(()-> string(hash(object)), objects, object)
    debug = summary(object) # TODO, probably slow, so needs a way of disabling
    print(io, "__lookup_interpolated('$(id)', '$(debug)')")
    return objects
end

function print_js_code(io::IO, x::Number, objects::IdDict)
    print(io, x)
    return objects
end

function print_js_code(io::IO, x::String, objects::IdDict)
    print(io, "'", x, "'")
    return objects
end

function print_js_code(io::IO, jss::JSString, objects::IdDict)
    print(io, jss.source)
    return objects
end

function print_js_code(io::IO, node::Node, objects::IdDict)
    print(io, "document.querySelector('[data-jscall-id=\"$(uuid(node))\"]')")
    return objects
end

function print_js_code(io::IO, jsc::JSCode, objects::IdDict)
    for elem in jsc.source
        print_js_code(io, elem, objects)
    end
    return objects
end

function print_js_code(io::IO, jsss::AbstractVector{JSCode}, objects::IdDict)
    for jss in jsss
        print_js_code(io, jss, objects)
        println(io)
    end
    return objects
end

function jsrender(session::Session, js::JSCode)
    # data_str = serialize_string(session, js)
    # Deserialize JSCode type and call it to run it!
    # TODO, stacktraces become truely terrible like this

    objects = IdDict()
    # Print code while collecting all interpolated objects in an IdDict
    code = sprint() do io
        print_js_code(io, js, objects)
    end
    # reverse lookup and serialize elements
    interpolated_objects = Dict(v => k for (k, v) in objects)
    data = Dict(
        :interpolated_objects => interpolated_objects,
        :source => code,
        :julia_file => js.file
    )
    data_str = serialize_string(session, interpolated_objects)
    src = """
        // JSCode from $(js.file)
        const data_str = '$(data_str)'
        console.log("ok lets do this")
        JSServe.base64decode(data_str).then(binary=> {
            const message = JSServe.decode_binary(binary);
            const objects = JSServe.deserialize_cached(message)
            function __lookup_interpolated(id) {
                return objects[id];
            }
            $code
        })
    """
    return DOM.script(src, type="module")
end
