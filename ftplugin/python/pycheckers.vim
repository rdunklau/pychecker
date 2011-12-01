" pychecker: a plugin for checking python code using pylint and pep8
"
python << EOF
from pep8 import Checker
import pep8
from optparse import OptionParser
import sys
import StringIO
import vim

from logilab.astng.builder import MANAGER
from pylint import lint, checkers

import os

# Pep8 module initialization
pep8.options = OptionParser()
pep8.options.count = 1
pep8.options.select = []
pep8.options.ignore = []
pep8.options.show_source = False
pep8.options.show_pep8 = False 
pep8.options.quiet = 0
pep8.options.repeat = True
pep8.options.verbose = 0
pep8.options.counters = dict.fromkeys(pep8.BENCHMARK_KEYS, 0)
pep8.options.physical_checks = pep8.find_checks('physical_line')
pep8.options.logical_checks = pep8.find_checks('logical_line')
pep8.options.messages = {}


# Pylint initialization
linter = lint.PyLinter()
checkers.initialize(linter)
linter.set_option('output-format', 'parseable')
linter.set_option('disable', vim.eval("g:PyLintDissabledMessages"))
linter.set_option('reports', 0)

def check_pylint():
    target = vim.eval('s:target')
    if os.path.exists(target or ''):
      MANAGER.astng_cache.clear()
      linter.reporter.out = StringIO.StringIO()
      linter.check(target)
      vim.command('let pylint_output = "%s"' % linter.reporter.out.getvalue()
          .replace('"', '\\"'))
    else:
      vim.command('let pylint_output = ""')


def check_pep8():
    target = vim.eval('s:target')
    if os.path.exists(target or ''):
      oldout = sys.stdout
      sys.stdout = result = StringIO.StringIO()
      Checker(target).check_all()
      sys.stdout = oldout
      vim.command('let pep8_output = "%s"' % result.getvalue()
          .replace('"', '\\"'))
    else:
      vim.command('let pep8_output = ""')


EOF

function! s:Update_Pep8()
  py check_pep8()
  for error in split(pep8_output, "\n")
      let b:parts = matchlist(error, '\([^:]*\):\(\d*\):\(\d*\): \(\w\d*\) \(.*\)')
      if len(b:parts) > 3
          " Store the error for the quickfix window
          let l:qf_item = {}
          let l:qf_item.filename = expand('%')
          let l:qf_item.bufnr = bufnr(b:parts[1])
          let l:qf_item.lnum = b:parts[2]
          let l:qf_item.type = b:parts[4]
          let l:qf_item.text = b:parts[5]
          call add(b:qf_list, l:qf_item)

      endif
  endfor
endfunction

function! s:Update_PyLint()
  py check_pylint()
  for error in split(pylint_output, "\n")
      let b:parts = matchlist(error, '\v([A-Za-z\.]+):(\d+): \[([EWRCI]+)[^\]]*\] (.*)')

      if len(b:parts) > 3

          " Store the error for the quickfix window
          let l:qf_item = {}
          let l:qf_item.filename = expand('%')
          let l:qf_item.bufnr = bufnr(b:parts[1])
          let l:qf_item.lnum = b:parts[2]
          let l:qf_item.type = b:parts[3]
          let l:qf_item.text = b:parts[4]
          call add(b:qf_list, l:qf_item)

      endif

  endfor
endfunction

function! s:ActivatePyCheckersQuickFixWindow()
    try
        silent colder 9 " go to the bottom of quickfix stack
    catch /E380:/
    endtry

    if s:pycheckers_qf > 0
        try
            exe "silent cnewer " . s:pycheckers_qf
        catch /E381:/
            echoerr "Could not activate PyCheckers Quickfix Window."
        endtry
    endif
endfunction


function! s:ClearPyCheckers()
    let s:matches = getmatches()
    for s:matchId in s:matches
        if s:matchId['group'] == 'PyFlakes'
            call matchdelete(s:matchId['id'])
        endif
    endfor
    let b:matched = []
    let b:matchedlines = {}
    let b:cleared = 1
endfunction


function! s:GetQuickFixStackCount()
    let l:stack_count = 0
    try
        silent colder 9
    catch /E380:/
    endtry

    try
        for i in range(9)
            silent cnewer
            let l:stack_count = l:stack_count + 1
        endfor
    catch /E381:/
        return l:stack_count
    endtry
endfunction


function! s:Update_QuickfixWindow()
  call setqflist(b:qf_list, 'r')
  if exists("s:pycheckers_qf")
    " if pyflakes quickfix window is already created, reuse it
    call s:ActivatePyCheckersQuickFixWindow()
    call setqflist(b:qf_list, 'r')
  else
    " one pyflakes quickfix window for all buffer
    call setqflist(b:qf_list, '')
    let s:pycheckers_qf = s:GetQuickFixStackCount()
  endif

  if len(b:qf_list)
    cwindow
  else
    cclose
  endif
endfunction


function! CheckBuffer()
  call s:ClearPyCheckers()
  let b:qf_list = []
  if &modifiable && &modified
	  write
  endif	
  let  s:target = expand('%:p')
  call s:Update_PyLint()
  call s:Update_Pep8()
  call s:Update_QuickfixWindow()
  call s:PlaceSigns()
endfunction

sign define W text=WW texthl=Todo
sign define C text=CC texthl=Comment
sign define R text=RR texthl=Visual
sign define E text=EE texthl=Error


function! s:PlaceSigns()
    "first remove all sings
    sign unplace *
    "now we place one sign for every quickfix line
    let l:id = 1
    for item in getqflist()
        execute(':sign place '.l:id.' name='.l:item.type.' line='.l:item.lnum.' buffer='.l:item.bufnr)
        let l:id = l:id + 1
    endfor
endfunction

autocmd BufWritePost <buffer> :call CheckBuffer()
