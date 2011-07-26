%% @author Gabriel Grise <ggrise@ggri.se>
%% @copyright 2007 Gabriel Grise

-module(wkb_parser).
-author('ggrise@ggri.se').

-export([parse/1, parse_hex/1]).

get_type(Type) ->
	EType = Type band (bnot (16#80000000 bor 16#20000000)),
	case EType of
		1 ->
			'Point';
		2 ->
			'LineString';
		3 ->
			'Polygon';
		4 ->
			'MultiPoint';
		5 -> 
			'MultiLineString';
		6 ->
			'MultiPolygon';
		7 ->
			'GeometryCollection'
	end.

to_num(A) when A >= 65 andalso A =< 70 ->
	A-55;
to_num(A) when A >= 48 andalso A =< 57 ->
	A-48.

hex_to_binary([], Acc) ->
	list_to_binary(lists:reverse(Acc));
hex_to_binary([H,L|Hex], Acc) ->
	hex_to_binary(Hex, [to_num(H) * 16 + to_num(L) | Acc]).

%% @spec parse_hex(string()) -> {integer(), Geometry}
%% @doc Return the Geometry with SRID if present
parse_hex(Wkb) ->
	Bin = hex_to_binary(string:to_upper(Wkb), []),
	parse(Bin).

%% @spec parse(binary()) -> {integer(), Geometry}
%% @doc Return the Geometry with SRID if present
parse(Wkb) ->
	{Srid, {Geom, _}} = parse_geometry(Wkb),
	{Srid, Geom}.

get_has_z(Type) ->
	(Type band 16#80000000) =/= 0.
get_has_srid(Type) ->
	(Type band 16#20000000) =/= 0.

parse_geometry(<<0, Type:32/unsigned-integer-big, Geom/binary>>) ->
	HasZ = get_has_z(Type),
	case get_has_srid(Type) of
		true ->
			<<Srid:32/integer-big, NGeom/binary>> = Geom,
				{Srid, parse_geometry(big, HasZ, get_type(Type), NGeom)};
		_ ->
			{none, parse_geometry(big, HasZ, get_type(Type), Geom)}
	end;
parse_geometry(<<1, Type:32/unsigned-integer-little, Geom/binary>>) ->
	HasZ = get_has_z(Type),
	case get_has_srid(Type) of
		true ->
			<<Srid:32/integer-little, NGeom/binary>> = Geom,
				{Srid, parse_geometry(little, HasZ, get_type(Type), NGeom)};
		_ ->
			{none, parse_geometry(little, HasZ, get_type(Type), Geom)}
	end.


%WKBPoint
parse_geometry(big, false, 'Point', <<X:64/float-big, Y:64/float-big, R/binary>>) ->
	{{X, Y}, R};
parse_geometry(little, false,  'Point', <<X:64/float-little, Y:64/float-little, R/binary>>) ->
	{{X, Y}, R};
parse_geometry(big, true, 'Point', <<X:64/float-big, Y:64/float-big, Z:64/float-big, R/binary>>) ->
	{{X, Y, Z}, R};
parse_geometry(little, true,  'Point', <<X:64/float-little, Y:64/float-little, Z:64/float-little, R/binary>>) ->
	{{X, Y, Z}, R};


%WKBLineString
parse_geometry(big, HasZ, 'LineString', <<NumPoints:32/unsigned-integer-big, Points/binary>>) ->
	parse_linestring(big, HasZ, NumPoints, Points, []);
parse_geometry(little, HasZ, 'LineString', <<NumPoints:32/unsigned-integer-little, Points/binary>>) ->
	parse_linestring(little, HasZ, NumPoints, Points, []);

%WKBPolygon
parse_geometry(big, HasZ, 'Polygon', <<NumRings:32/unsigned-integer-big, Rings/binary>>) ->
	parse_polygon(big, HasZ, NumRings, Rings, []);
parse_geometry(little, HasZ, 'Polygon',  <<NumRings:32/unsigned-integer-little, Rings/binary>>) ->
	parse_polygon(little, HasZ, NumRings, Rings, []);

parse_geometry(big, HasZ, Type, <<Num:32/unsigned-integer-big, Geoms/binary>>) -> 
	{G, R} = parse_multi(HasZ, Num, Geoms, []),
	{{Type, G}, R};
parse_geometry(little, HasZ, Type, <<Num:32/unsigned-integer-little, Geoms/binary>>) ->
	{G, R} = parse_multi(HasZ, Num, Geoms, []),
	{{Type, G}, R}.

parse_linestring(_, _, 0, Remain, Acc) ->
	{lists:reverse(Acc), Remain};
parse_linestring(_, _, _, <<>>, Acc) ->
	{lists:reverse(Acc), <<>>};
parse_linestring(little, false, Count, <<X:64/float-little, Y:64/float-little, Points/binary>>, Acc) ->
	parse_linestring(little, false, Count-1, Points, [{X, Y} | Acc]);
parse_linestring(big, false, Count, <<X:64/float-big, Y:64/float-big, Points/binary>>, Acc) ->
	parse_linestring(big, false, Count-1, Points, [{X, Y} | Acc]);
parse_linestring(little, true, Count, <<X:64/float-little, Y:64/float-little, Z:64/float-little, Points/binary>>, Acc) ->
	parse_linestring(little, true, Count-1, Points, [{X, Y, Z} | Acc]);
parse_linestring(big, true, Count, <<X:64/float-big, Y:64/float-big, Z:64/float-little, Points/binary>>, Acc) ->
	parse_linestring(big, true, Count-1, Points, [{X, Y, Z} | Acc]).


parse_polygon(_, _,0, R, Acc) ->
	{{get_type(3), lists:reverse(Acc)}, R};
parse_polygon(_, _, _,  <<>>, Acc) ->
	{{get_type(3), lists:reverse(Acc)}, <<>>};

parse_polygon(little, Z, NumRings, <<NumPoints:32/unsigned-integer-little, Ring/binary>>, Acc) ->
	{Line, Remain} = parse_linestring(little, Z, NumPoints, Ring, []),
	parse_polygon(little, Z, NumRings-1, Remain, [Line|Acc]);
parse_polygon(big, Z, NumRings, <<NumPoints:32/unsigned-integer-big, Ring/binary>>, Acc) ->
	{Line, Remain} = parse_linestring(big, Z, NumPoints, Ring, []),
	parse_polygon(big, Z, NumRings-1, Remain, [Line|Acc]).

parse_multi(_, 0, R, Acc) ->
	{lists:reverse(Acc), R};
parse_multi(_, _, <<>>, Acc) ->
	{lists:reverse(Acc), <<>>};
parse_multi(Z, Num, Geoms, Acc) ->
	{_Srid, {Geom, Remain}} = parse_geometry(Geoms),	
	parse_multi(Z, Num, Remain, [Geom|Acc]).
