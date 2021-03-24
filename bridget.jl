import Base: map, ==, hash, print

const Occupancy = Int; const EMPTY=0; const BLACK=1; const WHITE=2; const DISABLED=3
@enum Pieces L=5 Z=10 O=15 T=20
const Square = Tuple{Int,Int,Int} # one voxel
const Squares = Set{Square} # a set of voxels
const Board = Array{Occupancy, 3}
const Spot = Tuple{Int, Int} # just x/y, ignoring height
# struct Shape
#     blocks::Squares # shape locations (assuming 0,0,0 is the top-left-bottom of the cube) - these squares need to be empty to put shape
#     overhang::Squares # squares that need to be non-empty to put
# end
# ==(shape1::Shape, shape2::Shape) = shape1.blocks == shape2.blocks && shape1.overhang == shape2.overhang
# hash(shape::Shape) = hash(shape.blocks) + hash(shape.overhang)
const Shape = NamedTuple{(:blocks, :overhang), Tuple{Squares, Squares}}
const Move = NamedTuple{(:piece, :shape, :spot, :colour), Tuple{Pieces, Shape, Spot, Occupancy}}
EMPTY_MOVE = Move((O, Shape((Squares(), Squares())), (0,0), DISABLED))

struct StaticState

end

const PieceShapes = Dict(
    L => Shape((Set([(0,0,0), (1,0,0), (2,0,0), (2,1,0)]), Set{Squares}())), # L flat    
    O => Shape((Set([(0,0,0), (0,1,0), (1,0,0), (1,1,0)]), Set{Squares}())), # O flat    
    T => Shape((Set([(0,0,0), (1,0,0), (2,0,0), (1,1,0)]), Set{Squares}())), # T flat    
    Z => Shape((Set([(0,0,0), (1,0,0), (1,1,0), (2,1,0)]), Set{Squares}())), # Z flat    
    # Shape((Set([(0,0,0), (0,1,0), (0,0,1), (0,1,1)]), Set{Squares}())), # O horizontal
    # Shape((Set([(0,0,0), (1,0,0), (0,0,1), (1,0,1)]), Set{Squares}())), # O vertial
)

map(fun, dict::Dict) =  Dict(pair[1] => fun(pair[2]) for pair in dict)
map(fun, set::Set) =  Set([fun(x) for x in set])

mutable struct State
    board::Board
    white_pieces::Vector{Pieces}
    black_pieces::Vector{Pieces}
    whites_turn::Bool
    squares_to_connect::Vector{Tuple{Squares, Squares}}
    last_move::Move
end

function State()
    board = zeros(Occupancy,8,8,3)
    
    max_x, max_y, max_z = size(board)
    min_x, min_y, min_z = (1,1,1)
    left_side = [(x,y,z) for x = min_x for y = min_y:max_y for z = min_z:max_z]
    right_side = [(x,y,z) for x = max_x for y = min_y:max_y for z = min_z:max_z]
    top_side = [(x,y,z) for x = min_x:max_x for y = min_y for z = min_z:max_z]
    bottom_side = [(x,y,z) for x = min_x:max_x for y = max_y for z = min_z:max_z]
    squares_to_connect = [
        (Squares(left_side), Squares(right_side)),
        (Squares(top_side), Squares(bottom_side)),
        ]

    State(
        board,
        [L, L, L, L, Z, Z, Z, Z, T, T, T, T, O, O],
        [L, L, L, L, Z, Z, Z, Z, T, T, T, T, O, O],
        true,
        squares_to_connect,
        EMPTY_MOVE
    ) # default board
end

const piece_state = State(zeros(Occupancy,3,3,3), [], [], true, [], EMPTY_MOVE)
# const squares_to_connect = Vector{Tuple{Squares, Squares}}() # defines win condition

function HasSomeoneWon(state::State, last_move::Move)
    # if one of the BridgeComponents of a colour contains squares on opposing edges
    if IsBridgeBuilt(state, last_move)
        return (true, last_move.colour)
    end
    # game over, but nobody won
    if isempty(state.white_pieces) && isempty(state.black_pieces)
        return (true, DISABLED)
    end
    # nope, play on
    return (false, DISABLED)
end

function top_square(state::State, spot::Spot)
    spot_column = state.board[spot..., :]
    if spot_column[3] in [BLACK, WHITE]
        return (3, spot_column[3])
    elseif spot_column[2] in [BLACK, WHITE]
        return (2, spot_column[2])
    elseif spot_column[1] in [BLACK, WHITE]
        return (1, spot_column[1])
    else
        return (0, EMPTY)
    end
end

function BridgeNeighbours(board::Board, square::Square)
    # Neighbours of a square that can participate in a bridge
    # square needs to be on top, connections are North, West, East, South on the same level or one 
    # level up/down
    #TODO two levels when all colours are the same :(
    #TODO column major bug? 
    colour = board[square...]
    max_x, max_y, max_z = size(board)
    min_x, min_y, min_z = (1,1,1)
    possible_neighbour_spots = [
        (square[1] + 1, square[2], top_squares(square[1] + 1, square[2])),
        (square[1] - 1, square[2], top_squares(square[1] - 1, square[2])),
        (square[1], square[2] + 1, top_squares(square[1], square[2] + 1)),
        (square[1], square[2] - 1, top_squares(square[1], square[2] - 1)),
    ]
    possible_neighbours = [(x,y,z) for (x,y,z,col) in possible_neighbour_spots if col=colour]
    # TODO: special case with 1,3 and 3,1
    if square[3] == 3 && new_square[3] == 1 && board[new_square[1], new_square[2], 2] != colour ||
       square[3] == 1 && new_square[3] == 3 && board[square[1], square[2], 2] != colour
    # possible_neighbours = [(x,y,z) for (x,y,z)=possible_neighbours if min_x <= x <= max_x && min_y <= y <= max_y && min_z <= z <= max_z && on_top(board, x, y, z) && board[x,y,z] == colour]
    return Set(possible_neighbours)
end

on_top(board, x, y, z) = z == size(board)[3] || board[x,y,z+1] == EMPTY

function IsBridgeBuilt(state::State, last_move::Move)
    # has a bridge been formed?
    bollocks = squares_in_spot(last_move.shape.blocks, last_move.spot)
    bridge_to = Squares()
    for pairs in state.squares_to_connect
        # if we connected to a side this move, see if we can make it to the other side
        if !isempty(intersect(pairs[1], bollocks))
            bridge_to = union(bridge_to, pairs[2])
        end
        if !isempty(intersect(pairs[2], bollocks))
            bridge_to = union(bridge_to, pairs[1])
        end
    end

    if isempty(bridge_to) return (false) end

    starting_block = [(x,y,z) for (x,y,z)=bollocks if on_top(state.board, x, y, z)][1] # something on top - should we choose one on the side?
    @assert state.board[starting_block...] == last_move.colour
    reachable_blocks = connected_component(state.board, starting_block)
    bridge_built = !isempty(intersect(reachable_blocks, bridge_to))
    return bridge_built
end

function connected_component(board::Board, starting_block::Square)
    @assert on_top(board, starting_block...)
    component = Squares([starting_block])
    new_squares = Squares([starting_block])
    while true
        neighbouring_squares = [BridgeNeighbours(board, square) for square=new_squares]
        neighbouring_squares = union(neighbouring_squares...)
        new_squares = setdiff(neighbouring_squares, component)
        component = union(component, neighbouring_squares)
        if isempty(new_squares) break end
    end
    return component
end

function empty_and_occupied_sqares(board::Array{Occupancy, 3})
    empty_squares = Squares()
    occupied_squares = Squares()

    xlim, ylim, zlim = size(board)
    for z in 1:zlim
        for y in 1:ylim
            for x in 1:xlim
                if board[x,y,z] == EMPTY
                    push!(empty_squares, (x,y,z))
                elseif board[x,y,z] != DISABLED
                    push!(occupied_squares, (x,y,z))
                end
            end
        end
    end
    return empty_squares, occupied_squares
end

function can_put(board, shape::Shape, x_pos, y_pos)
    # TODO: make sure it fits... 2 disabled rows/columns?
    has_space = all([board[x_pos + x, y_pos + y , z + 1] == EMPTY for (x,y,z) = shape.blocks])
    no_overhang = all([board[x_pos + x, y_pos + y , z + 1] != EMPTY for (x,y,z) = shape.overhang])
    return has_space && no_overhang
end

function rotations(shape::Shape)
    all_shapes = Set{Shape}()
    for z=1:4
        for y=1:4
            for x=1:4
                push!(all_shapes, shape)
                shape = apply_rotate(x_rotate, shape)
            end
            shape = apply_rotate(y_rotate, shape)
        end
        shape = apply_rotate(z_rotate, shape)
    end
    return all_shapes
end

function apply_rotate(fun, shape)
    blocks = map(fun, shape.blocks)
    blocks = adjust_shape_vec(blocks)
    overhang = calculate_overhang(blocks)
    return Shape((blocks, overhang))
end

const ROT_MAX = 2
x_rotate(square::Square) = (square[1], square[3], ROT_MAX-square[2])
y_rotate(square::Square) = (ROT_MAX-square[3], square[2], square[1])
z_rotate(square::Square) = (square[2], ROT_MAX-square[1], square[3])

function adjust_shape_vec(squares::Squares)
    # make sure lowest coordinate is 0 (x,y and z)
    min_x = min([x for (x,y,z) = squares]...)
    min_y = min([y for (x,y,z) = squares]...)
    min_z = min([z for (x,y,z) = squares]...)
    new_blocks = map(square -> (square[1] - min_x, square[2] - min_y, square[3] - min_z), squares) 
    return new_blocks
end

squares_in_spot(squares::Squares, spot::Spot) = map(square -> (square[1] + spot[1], square[2] + spot[2], square[3] + 1), squares) 

# suares under this one
underlings(square::Square) = Set([(square[1], square[2], square[3]-i) for i = 1:square[3]])

function calculate_overhang(blocks::Squares)
    overhangs = union([underlings(square) for square = blocks]...)
    return setdiff(overhangs, blocks)
end

const PieceRotations = map(rotations, PieceShapes)

#TODO speedup: all_possible_moves in advance, and remove impossible ones as we go + can_put

function valid_moves(state::State)
    colour = state.whites_turn ? WHITE : BLACK
    possible_moves = Vector{Move}()
    # all_moves = Vector{Shape}()
    empty_squares, occupied_squares = empty_and_occupied_sqares(state.board)
    available_pieces = colour == WHITE ? unique(state.white_pieces) : unique(state.black_pieces)
    #uses PieceRotations and the board
    for x in 1:size(state.board)[1]
        for y in 1:size(state.board)[1]
            for piece in available_pieces
                for rotation in PieceRotations[piece]
                    # push!(all_moves, rotation)
                    if issubset(squares_in_spot(rotation.blocks, (x,y)), empty_squares) && issubset(squares_in_spot(rotation.overhang, (x,y)), occupied_squares)
                    # if can_put(state.board, rotation, x, y)
                        push!(possible_moves, Move((piece, rotation, (x, y), colour)))
                    end
                end
            end
        end
    end
    return possible_moves
end

function make_move!(state::State, move::Move)
    for square in move.shape.blocks
        @assert state.board[square[1] + move.spot[1], square[2] + move.spot[2], square[3] + 1] == EMPTY
        state.board[square[1] + move.spot[1], square[2] + move.spot[2], square[3] + 1] = move.colour
    end
    if state.whites_turn # TODO: dict of defaultdict
        deleteat!(state.white_pieces, findfirst(x->x==move.piece, state.white_pieces))
    else
        deleteat!(state.black_pieces, findfirst(x->x==move.piece, state.black_pieces))
    end
    state.whites_turn = !state.whites_turn
    state.last_move = move
end

function valid_moves_spot(state::State, spot::Spot, shape::Shape)
    #piece will go in a 3x3x3 cube centered at spot. With the heights known (0,1,2,X) this can 
    #be precalculated for every board combination and every piece rotation, and pulled from a cache

    #to make it unique, piece has to occupy a spot on both the top and left side (cache might only contain these)
end

function print(shape::Shape)

end


const blocks = ["■□▣◾◼◻◽"]


const board_show = 
"..1221.
...1..." # colors: black - black top and under, color indicates if bottom is different https://stackoverflow.com/questions/27929766/how-to-print-text-with-a-specified-rgb-value-in-julia

# Random policy
function next_move_random(state::State, possible_moves::Vector{Move})
    selected_move = rand(possible_moves)
    return selected_move
end

function play_game(white_policy, black_policy)
    state = State()
    game_over, winner = false, DISABLED
    while true
        print('.')
        possible_moves = valid_moves(state)
        if isempty(possible_moves) 
            print("No valid moves")
            break
        end
        next_move = state.whites_turn ? white_policy(state, possible_moves) : black_policy(state, possible_moves)
        make_move!(state, next_move)
        game_over, winner = HasSomeoneWon(state, next_move)
        game_over && break
    end
    print("Game over, Winner: is $winner")
    return state, winner
end

state, winner = play_game(next_move_random, next_move_random)