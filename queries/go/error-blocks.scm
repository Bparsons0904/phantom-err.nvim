;; Query for basic if err != nil blocks
(if_statement
  condition: (binary_expression
    left: (identifier) @err_var
    operator: "!="
    right: (nil)
  )
  consequence: (block)
) @if_block
(#eq? @err_var "err")
