" we need the conceal feature (vim ≥ 7.3)
if !has('conceal')
    finish
endif

" remove the keywords. we'll re-add them below
syntax clear pythonOperator


syntax match pythonOperator "\<is\>"                 conceal cchar=⇒
syntax match pyNiceOperator "\<in\>"                 conceal cchar=∈
syntax match pyNiceOperator "\<not in\>"             conceal cchar=∉
syntax match pyNiceOperator "\<or\>"                 conceal cchar=∨
syntax match pyNiceOperator "\<and\>"                conceal cchar=∧
" syntax match pyNiceOperator "for\%( \+\)\w\+\%( \)"conceal cchar=⑁
syntax match pyNiceOperator "\<not\%( \|\>\)"        conceal cchar=¬
syntax match pyNiceOperator "\<not\%( \|\>\)"        conceal cchar=᨟
syntax match pyNiceOperator "<="                     conceal cchar=≤
syntax match pyNiceOperator ">="                     conceal cchar=≥
syntax match pyNiceOperator "=\@<!===\@!"            conceal cchar=≡
syntax match pyNiceOperator "!="                     conceal cchar=≢
syntax match pyNiceOperator "\<\%(math\.\)\?sqrt\>"  conceal cchar=√
syntax match pyNiceKeyword "\<\%(math\.\)\?pi\>"     conceal cchar=π
syntax match pyNiceOperator " \* "                   conceal cchar=∙
syntax match pyNiceOperator " / "                    conceal cchar=÷
syntax match pyNiceOperator "\<\%(math\.\|\)ceil\>"  conceal cchar=⌈
syntax match pyNiceOperator "\<\%(math\.\|\)floor\>" conceal cchar=⌊
syntax keyword pyNiceStatement with                  conceal cchar=⋽
syntax keyword pyNiceStatement as                    conceal cchar=⇔
syntax keyword pyNiceBuiltin   len                   conceal cchar=#
syntax keyword pyNiceBuiltin   list                  conceal cchar=┋
syntax keyword pyNiceBuiltin   str                   conceal cchar=α
syntax keyword pyNiceBuiltin   range                 conceal cchar=⩥
syntax keyword pyNiceStatement break                 conceal cchar=¦
syntax keyword pyNiceOperator  def                   conceal cchar=ϝ
syntax keyword pyNiceOperator  sum                   conceal cchar=∑
syntax keyword pyNiceOperator  for                   conceal cchar=🜊
syntax keyword pyNiceOperator  continue              conceal cchar=⋱
syntax keyword pyNiceStatement int                   conceal cchar=ℤ
syntax keyword pyNiceStatement float                 conceal cchar=ℝ
syntax keyword pyNiceStatement complex               conceal cchar=ℂ
syntax keyword pyNiceStatement False                 conceal cchar=⊭
syntax keyword pyNiceStatement True                  conceal cchar=⊨
syntax keyword pyNiceStatement lambda                conceal cchar=λ
syntax keyword pyNiceStatement return                conceal cchar=⇐
syntax keyword pyNiceStatement input                 conceal cchar=ί
syntax keyword pyNiceStatement import                conceal cchar=Ϡ
syntax keyword pyNiceStatement from                  conceal cchar=⊶
syntax keyword pyNiceStatement None                  conceal cchar=∅
syntax keyword pyNiceStatement if                    conceal cchar=⑆
syntax keyword pyNiceStatement elif                  conceal cchar=⑇
syntax keyword pyNiceStatement else                  conceal cchar=⑈
syntax keyword pyNiceStatement while                 conceal cchar=♭
syntax keyword pyNiceStatement try                   conceal cchar=〒
syntax keyword pyNiceStatement except                conceal cchar=〆
syntax keyword pyNiceStatement pass                  conceal cchar=֍
syntax keyword pyNiceStatement raise                 conceal cchar=↑
syntax keyword pyNiceStatement global                conceal cchar=🌐
syntax keyword pyNiceStatement file                  conceal cchar=🗃
syntax keyword pyNiceStatement filter                conceal cchar=Ÿ
syntax keyword pyNiceStatement sorted                conceal cchar=Δ
syntax keyword pyNiceStatement self                  conceal cchar=ϡ
syntax keyword pyNiceStatement print                 conceal cchar=≫

" 䭍
" —
" Ѧ
" ࿕
" ࿐
" ༆
" ৠ
" ⎋ 

hi link pyNiceOperator Operator
hi link pyNiceStatement Statement
hi link pyNiceKeyword Keyword
hi! link Conceal Operator

setlocal conceallevel=1
syntax keyword pyNiceBuiltin all conceal cchar=∀
syntax keyword pyNiceBuiltin any conceal cchar=∃
