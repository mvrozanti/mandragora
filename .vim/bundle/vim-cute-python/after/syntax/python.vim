" we need the conceal feature (vim ≥ 7.3)
if !has('conceal')
    finish
endif

" remove the keywords. we'll re-add them below
syntax clear pythonOperator

" syntax match pythonOperator "\<is\>" conceal cchar=≡
syntax match pyNiceOperator "\<in\>" conceal cchar=∈
syntax match pyNiceOperator "\<not in\>" conceal cchar=∉
syntax match pyNiceOperator "\<or\>" conceal cchar=∨
syntax match pyNiceOperator "\<and\>" conceal cchar=∧
syntax match pyNiceOperator "\<not\%( \|\>\)" conceal cchar=¬
syntax match pyNiceOperator "<=" conceal cchar=≤
syntax match pyNiceOperator ">=" conceal cchar=≥
syntax match pyNiceOperator "=\@<!===\@!" conceal cchar=≡
syntax match pyNiceOperator "!=" conceal cchar=≢
syntax match pyNiceOperator "\<\%(math\.\)\?sqrt\>" conceal cchar=√
syntax match pyNiceKeyword "\<\%(math\.\)\?pi\>" conceal cchar=π
syntax match pyNiceOperator " \* " conceal cchar=∙
syntax match pyNiceOperator " / " conceal cchar=÷
syntax match pyNiceOperator "\<\%(math\.\|\)ceil\>" conceal cchar=⌈
syntax match pyNiceOperator "\<\%(math\.\|\)floor\>" conceal cchar=⌊
syntax keyword pyNiceStatement as conceal cchar=⇔
syntax keyword pyNiceBuiltin   len conceal cchar=#
syntax keyword pyNiceOperator  def conceal cchar=ϝ
syntax keyword pyNiceOperator  sum conceal cchar=∑
syntax keyword pyNiceOperator  for conceal cchar=⋱
syntax keyword pyNiceStatement int conceal cchar=ℤ
syntax keyword pyNiceStatement float conceal cchar=ℝ
syntax keyword pyNiceStatement complex conceal cchar=ℂ
syntax keyword pyNiceStatement False conceal cchar=✗
syntax keyword pyNiceStatement True conceal cchar=✓
syntax keyword pyNiceStatement lambda conceal cchar=λ
syntax keyword pyNiceStatement return conceal cchar=⇐
syntax keyword pynicestatement input conceal cchar=ί
syntax keyword pynicestatement import conceal cchar=Ϡ
syntax keyword pynicestatement None conceal cchar=∅
syntax keyword pynicestatement print conceal cchar=≫
syntax keyword pynicestatement if conceal cchar=⑁
syntax keyword pynicestatement elif conceal cchar=├
syntax keyword pynicestatement else conceal cchar=┚
syntax keyword pynicestatement while conceal cchar=♭
syntax keyword pynicestatement try conceal cchar=〒
syntax keyword pynicestatement except conceal cchar=〆
syntax keyword pynicestatement pass conceal cchar=—
syntax keyword pynicestatement raise conceal cchar=↑
syntax keyword pynicestatement global conceal cchar=●
syntax keyword pynicestatement file conceal cchar=▧

hi link pyNiceOperator Operator
hi link pyNiceStatement Statement
hi link pyNiceKeyword Keyword
hi! link Conceal Operator

setlocal conceallevel=1
syntax keyword pyNiceBuiltin all conceal cchar=∀
syntax keyword pyNiceBuiltin any conceal cchar=∃
