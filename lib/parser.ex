defmodule Dwarf.Parser do
  @moduledoc """
  	The parser takes a list of tokens and genarates an AST trees from it.
    The parse is a decent recursive parser.
  	This AST tree will be further optimized by the optimizer.

  	type of stmt =
  		{:assign,type,nameOfVar, expr} -> type nameOfVar := expr
  		{:print,expr} -> print expr
  		{:call,nameOfFunction,args} -> add(args)
  		{:dec,type,ident,expr} -> type ident := expr
      {:if,expr,true_stmt,false_stmt} -> if expr then true_stmt else false_stmt
      {:fun,name,args,stmt} -> fun name := (args) -> stmt

  	type of expr = 
  		{:op,expr,operator,expr2} = expr op expr2
  		{:uop,"!",expr} = !expr
  		{:var,identifier} -> var like a, foo, bar
  		 
    type of param = 
      {:param,type,name}
  """

  @doc """
  	Parses a list of tokens into an AST tree
  """

  def parse([]), do: []

  def parse(tokens) do
    {stmt, rest} = parse_stmt(tokens)
    [stmt | parse(rest)]
  end

  @spec parse_stmt(list) :: {list, list}
  defp parse_stmt([token | rest]) do
    # IO.inspect token
    case token do
      # parse the var declaration and continue with the rest
      {{:type, :fun}, _} ->
        parse_fun_dec([token | rest])

      {{:type, _}, _} ->
        parse_var_dec([token | rest])

      {{:if}, _} ->
        parse_if_stmt([token | rest])

      # print statement
      {{:print}, _} ->
        parse_print([token | rest])

      # assignmment such as a = a + 4
      {{:ident, _}, _} ->
        parse_assign([token | rest])

      # parse a list of statements
      {{:lcurly}, _} ->
        parse_stmts([token | rest])

      {{a, _}, line} ->
        raise "Parsing error : unexpected #{to_string(a)} on line : #{line}"

      {{a}, line} ->
        raise "Parsing error : unexpected #{to_string(a)} on line : #{line}"
    end
  end

  defp parse_stmt([]), do: []

  defp parse_factor([token | rest]) do
    case token do
      {:num, a} ->
        {{:num, a}, rest}

      {:string,str} ->
        {{:string,str},rest}

      {:bool,bool} ->
        {{:bool,bool},rest}
      {{:true},_} ->
        {{:bool,:true}, rest}

      {{:false},_} ->
        {{:bool,:false}, rest}

      {{:uop, op}, _} ->
        {expr, rest1} = parse_factor(rest)
        {:uop, op, expr}

      {{:ident, a}, _} ->
        case rest do
          [{{:lbracket}, _} | _] -> parse_func([token | rest])
          _ -> {{:var, a}, rest}
        end

      {{:lbracket}, _} ->
        {expr, rest1} = parse_exp(rest)

        case rest1 do
          [{{:rbracket}, _} | rest2] ->
            {expr, rest2}

          [{_, line}] ->
            raise "Parsing error: expected a ) on line #{line}"

          [] ->
            raise "Parsing error: unexpected end of file in a bracketised expression"
        end

      {a, line} ->
        raise "Parsing Error : expected a factor but got #{Enum.join(Tuple.to_list(a))} on line #{
                line
              }"
    end
  end

  # look for the rest of operators with medium precedence
  defp parse_term([]), do: raise ("Parsing error : End of file while trying to parse a term")
  defp parse_term(tokens) do
    {l_expr,rest} = parse_factor(tokens)
    case rest do
      [{{:op, :mul}, _} | rest1] ->
        {r_expr, rest2} = parse_term(rest1)
        {{:op, :mul, l_expr, r_expr}, rest2}
      [{{:op, :div}, _} | rest1] ->
        {r_expr, rest2} = parse_term(rest1)
        {{:op, :div, l_expr, r_expr}, rest2}
      [{{:op, :mod}, _} | rest1] ->
        {r_expr, rest2} = parse_term(rest1)
        {{:op, :mod, l_expr, r_expr}, rest2}
      _ -> 
        {l_expr,rest}
    end
  end

  # look for operator with low precedence like addition or substraction 
  # and then look for term 
  defp parse_op(tokens) do
    {l_expr,rest} = parse_term(tokens)
    case rest do
       [{{:op, :add}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :add, l_expr, r_expr}, rest2}
      [{{:op, :sub}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :sub, l_expr, r_expr}, rest2}
      [{{:op, :ge}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :ge, l_expr, r_expr}, rest2}
      [{{:op, :gt}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :gt, l_expr, r_expr}, rest2}
      [{{:op, :se}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :se, l_expr, r_expr}, rest2}
      [{{:op, :st}, _} | rest1] ->
        {r_expr, rest2} = parse_op(rest1)
        {{:op, :st, l_expr, r_expr}, rest2}
      _ ->
        {l_expr, rest}
    end
  end
  defp parse_exp([]), do: raise("Parsing error: End of file while trying to parse an expression")
  @spec parse_exp(list) :: {tuple, list}
  defp parse_exp(tokens) do

    {l_expr, rest} = parse_op(tokens)
    case rest do
      [{{:op, :concat}, _} | rest1] ->
        {r_expr, rest2} = parse_exp(rest1)
        {{:op, :concat, l_expr, r_expr}, rest2}
      _ ->
        {l_expr, rest}
    end
  end

  # Parse a list of statement and return a list of statements and the rest of the tokens.
  @spec parse_stmts(list) :: {list, list}
  defp parse_stmts([token | rest]) do
    case token do
      {{:lcurly}, _} ->
        {stmt, rest1} = parse_stmt(rest)
        {stmts, rest2} = parse_stmts(rest1)
        {[stmt | stmts], rest2}

      {{:rcurly}, _} ->
        {[], rest}

      {a, line} ->
        raise "Parsing Error : expected a { but got #{Enum.join(Tuple.to_list(a))} on line #{line}"
    end
  end

  defp parse_func([token | rest]) do
    case token do
      {{:ident, a}, _} ->
        case rest do
          [{{:lbracket}, _} | [{{:rbracket}, _} | rest1]] ->
            {{:call, a, []}, rest1}

          [{{:lbracket}, _} | rest1] ->
            {args, rest2} = parse_args(rest1)

            case rest2 do
              [{{:rbracket}, _} | rest3] -> {{:call, a, args}, rest3}
              {_, line} -> raise "Parser error : Expected a ) on line #{line}"
            end

          [{_, line} | _] ->
            raise "Parser error : parsing a function without a ( on line #{line}"
        end

      {_, line} ->
        raise "Parser error : Expected an identifier for a function on line #{line}"
    end
  end

  # parses the args of a function such as add(2+3,8)
  defp parse_args([token | rest]) do
    {node, rest1} = parse_exp([token | rest])

    case rest1 do
      [{{:coma}, _} | rest2] ->
        {args, rest3} = parse_args(rest2)
        {[node | args], rest3}

      _ ->
        {[node], rest1}
    end
  end

  defp parse_args([]), do: raise("Parsing Error: end of file while parsing args")

  @spec parse_var_dec(list) :: {tuple, list}
  defp parse_var_dec([token | rest]) do
    case rest do
      [] ->
        {a, line} = token

        raise "Parsing error : unexpected end of file in var dec after #{
                Enum.join(Tuple.to_list(a))
              } on line : #{line}"

      [{{:ident, a}, _} | rest1] ->
        case rest1 do
          [{{:dec}, _} | rest2] ->
            {exp, rest3} = parse_exp(rest2)
            {type, _} = token
            {{:dec, type, a, exp}, rest3}

          [{a, line} | _] ->
            raise "Parsing error : expected := but got #{Enum.join(Tuple.to_list(a))} on line #{
                    line
                  }"
        end

      [{a, line} | _] ->
        raise "Parsing error : expected a var name but got #{Enum.join(Tuple.to_list(a))} on line : #{
                line
              }"
    end
  end

  defp parse_var_dec([]),
    do: raise("Parsing Error: end of file while parsing a variable declaration")

  # Parse a function declaration
  # To create a function "fun nameOfFunction := (int param1, fun param2) -> expr"
  defp parse_fun_dec([token | rest]) do
    case token do
      {{:type, :fun}, _} ->
        case rest do
          [{{:ident, function_name}, _} | rest1] ->
            case rest1 do
              [{{:dec}, _} | rest2] ->
                case rest2 do
                  [{{:lbracket}, _} | [{{:rbracket}, _} | rest3]] ->
                    {expr, rest4} = parse_exp(rest3)
                    {{:fun, function_name, [], expr}, rest4}

                  [{{:lbracket}, _} | rest1] ->
                    {args, rest2} = parse_params(rest1)
                    case rest2 do
                      [{{:rbracket}, _} | [{{:arrow}, _} | rest3]] ->
                        {expr, rest4} = parse_exp(rest3)
                        {{:fun, function_name, args, expr}, rest4}

                      [{_, line}|_] ->
                        raise "Parser error : Expected a ) on line #{line}"
                    end

                  {_, line} ->
                    raise "Parser error : parsing a function without a ( on line #{line}"
                end

              [{a, line} | _] ->
                raise "Parsing error : expected a := name received : #{
                        Enum.join(Tuple.to_list(a))
                      } on line : #{line}"
            end

          [{a, line} | _] ->
            raise "Parsing error : Expected a function name received : #{
                    Enum.join(Tuple.to_list(a))
                  } on line : #{line}"
        end

      {_, line} ->
        raise "Parsing error : Trying to parse a function declaration without starting with 'fun' on line #{
                line
              }"
    end
  end

  defp parse_params([]), do: raise "Parsing error : End of file expected a type"
  defp parse_params([token|rest]) do
    case token do
      {{:type,type},_} -> 
        case rest do
          [{{:ident,name},_}|rest1] -> 
            case rest1 do
              [{{:coma},_}|rest2] -> 
                {args,rest3} = parse_params(rest2)
                {[{:param,type,name} | args],rest3}
              _ -> {[{:param,type,name}],rest1}
            end
        end
      {a,line} -> 
        raise "Parsing error : Expected a type received #{
                    Enum.join(Tuple.to_list(a))
                  } on line : #{line}"
    end
  end

  defp parse_if_stmt([token | rest]) do
    case token do
      {{:if}, _} ->
        {expr, rest1} = parse_exp(rest)

        case rest1 do
          [{{:then}, _} | rest2] ->
            {true_stmt, rest3} = parse_stmt(rest2)

            case rest3 do
              [{{:else}, _} | rest4] ->
                {false_stmt, rest5} = parse_stmt(rest4)
                {{:if, expr, true_stmt, false_stmt}, rest5}

              [{a, line} | _] ->
                raise "Parsing error : Expected 'else' received : #{Enum.join(Tuple.to_list(a))} on line : #{
                        line
                      }"
            end

          [{_, line} | _] ->
            raise "Parsing error : Expected a then on line #{line}"

          [] ->
            raise "Parsing error : End of file expected then"
        end

      {a, line} ->
        raise "Parsing error : Expected 'if' received : #{Enum.join(Tuple.to_list(a))} on line : #{
                line
              }"
    end
  end

  defp parse_print([token | rest]) do
    case token do
      {{:print}, _} ->
        {exp, rest1} = parse_exp(rest)
        {{:print, exp}, rest1}

      {a, line} ->
        raise "Parsing error : expected a print got a #{to_string(a)} on line : #{line}"
    end
  end

  defp parse_assign([token | rest]) do
    case token do
      {{:ident, ident}, _} ->
        case rest do
          [{{:eq}, _} | rest1] ->
            {expr, rest2} = parse_exp(rest1)
            {{:assign, ident, expr}, rest2}

          [{a, line} | _] ->

            raise "Parsing error : expected an = but got : #{Enum.join(Tuple.to_list(a))} on line : #{
                    line
                  }"
        end

      {a, line} ->
        raise "Parsing error : expected a variable name received : #{Enum.join(Tuple.to_list(a))} on line : #{
                line
              }"
    end
  end
end
