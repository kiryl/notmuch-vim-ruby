if exists("g:loaded_notmuch_rb")
	finish
endif

if !has("ruby") || version < 700
	finish
endif

let g:loaded_notmuch_rb = "yep"

let g:notmuch_rb_folders_maps = {
	\ '<Enter>':	'folders_show_search()',
	\ 's':		'folders_search_prompt()',
	\ '=':		'folders_refresh()',
	\ 'm':		'show_compose()',
	\ }

let g:notmuch_rb_search_maps = {
	\ 'q':		'kill_this_buffer()',
	\ '<Enter>':	'search_show_thread(1)',
	\ '<Space>':	'search_show_thread(2)',
	\ 'A':		'search_tag("-inbox -unread")',
	\ 'I':		'search_tag("-unread")',
	\ 't':		'search_tag("")',
	\ 's':		'search_search_prompt()',
	\ '=':		'search_refresh()',
	\ '?':		'search_info()',
	\ 'm':		'show_compose()',
	\ }

let g:notmuch_rb_show_maps = {
	\ 'q':		'kill_this_buffer()',
	\ 'A':		'show_tag("-inbox -unread")',
	\ 'I':		'show_tag("-unread")',
	\ 't':		'show_tag("")',
	\ 'o':		'show_open_msg()',
	\ 'e':		'show_extract_msg()',
	\ 'r':		'show_reply()',
	\ '?':		'show_info()',
	\ '<Tab>':	'show_next_msg()',
	\ 'm':		'show_compose()',
	\ }

let g:notmuch_rb_compose_maps = {
	\ ',s':		'compose_send()',
	\ ',q':		'compose_quit()',
	\ }

let s:notmuch_rb_folders_default = [
	\ [ 'new', 'tag:inbox and tag:unread' ],
	\ [ 'inbox', 'tag:inbox' ],
	\ [ 'unread', 'tag:unread' ],
	\ ]

let s:notmuch_rb_date_format_default = '%d.%m.%y'
let s:notmuch_rb_datetime_format_default = '%d.%m.%y %H:%M:%S'
let s:notmuch_rb_reader_default = 'terminal -e "mutt -f %s"'
let s:notmuch_rb_sendmail_default = '/usr/sbin/sendmail'
let s:notmuch_rb_folders_count_threads_default = 0

if !exists('g:notmuch_rb_date_format')
	let g:notmuch_rb_date_format = s:notmuch_rb_date_format_default
endif

if !exists('g:notmuch_rb_datetime_format')
	let g:notmuch_rb_datetime_format = s:notmuch_rb_datetime_format_default
endif

if !exists('g:notmuch_rb_reader')
	let g:notmuch_rb_reader = s:notmuch_rb_reader_default
endif

if !exists('g:notmuch_rb_sendmail')
	let g:notmuch_rb_sendmail = s:notmuch_rb_sendmail_default
endif

if !exists('g:notmuch_rb_folders_count_threads')
	let g:notmuch_rb_folders_count_threads = s:notmuch_rb_folders_count_threads_default
endif

function! s:new_file_buffer(type, fname)
	exec printf('edit %s', a:fname)
	execute printf('set filetype=notmuch-%s', a:type)
	execute printf('set syntax=notmuch-%s', a:type)
	ruby $buf_queue.push($curbuf.number)
endfunction

"" actions

function! s:show_next_msg()
ruby << EOF
	r, c = $curwin.cursor
	n = $curbuf.line_number
	i = $messages.index { |m| n >= m.start && n <= m.end }
	m = $messages[i + 1]
	if m
		r = m.body_start + 1
		VIM::command("normal #{m.start}zt")
		$curwin.cursor = r, c
	end
EOF
endfunction

function! s:show_compose()
	ruby open_compose
endfunction

function! s:show_reply()
	ruby open_reply get_message.mail
endfunction

function! s:show_info()
	ruby vim_puts get_message.inspect
endfunction

function! s:show_extract_msg()
ruby << EOF
	m = get_message
	m.mail.attachments.each do |a|
		File.open(a.filename, 'w') do |f|
			f.write a.body.decoded
			print "Extracted '#{a.filename}'"
		end
	end
EOF
endfunction

function! s:show_open_msg()
ruby << EOF
	m = get_message
	mbox = File.expand_path('~/.notmuch/vim_mbox')
	cmd = VIM::evaluate('g:notmuch_rb_reader') % mbox
	system "notmuch show --format=mbox id:#{m.message_id} > #{mbox} && #{cmd}"
EOF
endfunction

function! s:show_tag(intags)
	if empty(a:intags)
		let tags = input('tags: ')
	else
		let tags = a:intags
	endif
	ruby do_tag(get_cur_view, VIM::evaluate('l:tags'))
	call s:show_next_thread()
endfunction

function! s:search_search_prompt()
	let text = input('Search: ')
	setlocal modifiable
ruby << EOF
	$cur_search = VIM::evaluate('text')
	search_render($cur_search)
EOF
	setlocal nomodifiable
endfunction

function! s:search_info()
	ruby vim_puts get_thread_id
endfunction

function! s:search_refresh()
	setlocal modifiable
	ruby search_render($cur_search)
	setlocal nomodifiable
endfunction

function! s:search_tag(intags)
	if empty(a:intags)
		let tags = input('tags: ')
	else
		let tags = a:intags
	endif
	ruby do_tag(get_thread_id, VIM::evaluate('l:tags'))
	norm j
	call s:search_refresh()
endfunction

function! s:folders_search_prompt()
	let text = input('Search: ')
	call s:search(text)
endfunction

function! s:folders_refresh()
	setlocal modifiable
	ruby folders_render()
	setlocal nomodifiable
endfunction

"" basic

function! s:show_cursor_moved()
ruby << EOF
	if $render.is_ready?
		VIM::command('setlocal modifiable')
		$render.do_next
		VIM::command('setlocal nomodifiable')
	end
EOF
endfunction

function! s:show_next_thread()
	call s:kill_this_buffer()
	if line('.') != line('$')
		norm j
		call s:search_show_thread(0)
	else
		echo 'No more messages.'
	endif
endfunction

function! s:kill_this_buffer()
	bdelete!
ruby << EOF
	$buf_queue.pop
	b = $buf_queue.last
	VIM::command("buffer #{b}") if b
EOF
endfunction

function! s:set_map(maps)
	nmapclear <buffer>
	for [key, code] in items(a:maps)
		let cmd = printf(":call <SID>%s<CR>", code)
		exec printf('nnoremap <buffer> %s %s', key, cmd)
	endfor
endfunction

function! s:set_ruby_map(maps)
	nmapclear <buffer>
	for [key, code] in items(a:maps)
		exec printf('nnoremap <buffer> %s :ruby %s<CR>', key, code)
	endfor
endfunction

function! s:new_buffer(type)
	enew
	setlocal buftype=nofile bufhidden=hide
	keepjumps 0d
	execute printf('set filetype=notmuch-%s', a:type)
	execute printf('set syntax=notmuch-%s', a:type)
	ruby $buf_queue.push($curbuf.number)
endfunction

function! s:set_menu_buffer()
	setlocal nomodifiable
	setlocal cursorline
	setlocal nowrap
endfunction

"" main

function! s:show(thread_id)
	call s:new_buffer('show')
	setlocal modifiable
ruby << EOF
	thread_id = VIM::evaluate('a:thread_id')
	$cur_thread = thread_id
	$messages.clear
	$curbuf.render do |b|
		do_read do |db|
			q = db.query(get_cur_view)
			q.sort = 0
			msgs = q.search_messages
			msgs.each do |msg|
				m = Mail.read(msg.filename)
				part = m.find_first_text
				nm_m = Message.new(msg, m)
				$messages << nm_m
				date_fmt = VIM::evaluate('g:notmuch_rb_datetime_format')
				date = Time.at(msg.date).strftime(date_fmt)
				nm_m.start = b.count
				b << "%s %s (%s)" % [msg['from'], date, msg.tags]
				b << "Subject: %s" % [msg['subject']]
				b << "To: %s" % m['to']
				b << "Cc: %s" % m['cc']
				b << "Date: %s" % m['date']
				nm_m.body_start = b.count
				b << "--- %s ---" % part.mime_type
				part.convert.each_line do |l|
					b << l.chomp
				end
				b << ""
				nm_m.end = b.count
			end
			b.delete(b.count)
		end
	end
	$messages.each_with_index do |msg, i|
		VIM::command("syntax region nmShowMsg#{i}Desc start='\\%%%il' end='\\%%%il' contains=@nmShowMsgDesc" % [msg.start, msg.start + 1])
		VIM::command("syntax region nmShowMsg#{i}Head start='\\%%%il' end='\\%%%il' contains=@nmShowMsgHead" % [msg.start + 1, msg.body_start])
		VIM::command("syntax region nmShowMsg#{i}Body start='\\%%%il' end='\\%%%dl' contains=@nmShowMsgBody" % [msg.body_start, msg.end])
	end
EOF
	setlocal nomodifiable
	call s:set_map(g:notmuch_rb_show_maps)
endfunction

function! s:search_show_thread(mode)
ruby << EOF
	mode = VIM::evaluate('a:mode')
	id = get_thread_id
	case mode
	when 0;
	when 1; $cur_filter = nil
	when 2; $cur_filter = $cur_search
	end
	VIM::command("call s:show('#{id}')")
EOF
endfunction

function! s:search(search)
	call s:new_buffer('search')
ruby << EOF
	$cur_search = VIM::evaluate('a:search')
	search_render($cur_search)
EOF
	call s:set_menu_buffer()
	call s:set_map(g:notmuch_rb_search_maps)
	autocmd CursorMoved <buffer> call s:show_cursor_moved()
endfunction

function! s:folders_show_search()
ruby << EOF
	n = $curbuf.line_number
	s = $searches[n - 1]
	VIM::command("call s:search('#{s}')")
EOF
endfunction

function! s:folders()
	call s:new_buffer('folders')
	ruby folders_render()
	call s:set_menu_buffer()
	call s:set_map(g:notmuch_rb_folders_maps)
endfunction

"" root

function! s:set_defaults()
	if exists('g:notmuch_rb_custom_search_maps')
		call extend(g:notmuch_rb_search_maps, g:notmuch_rb_custom_search_maps)
	endif

	if exists('g:notmuch_rb_custom_show_maps')
		call extend(g:notmuch_rb_show_maps, g:notmuch_rb_custom_show_maps)
	endif

	" TODO for now lets check the old folders too
	if !exists('g:notmuch_rb_folders')
		if exists('g:notmuch_folders')
			let g:notmuch_rb_folders = g:notmuch_folders
		else
			let g:notmuch_rb_folders = s:notmuch_rb_folders_default
		endif
	endif
endfunction

function! s:NotMuchR()
	call s:set_defaults()

ruby << EOF
	require 'notmuch'
	require 'rubygems'
	require 'mail'
	require 'tempfile'
	require 'open3'

	$db_name = nil
	$email_address = nil
	$searches = []
	$buf_queue = []
	$threads = []
	$messages = []
	$config = {}

	def get_config
		group = nil
		config = ENV['NOTMUCH_CONFIG'] || '~/.notmuch-config'
		File.open(File.expand_path(config)).each do |l|
			l.chomp!
			case l
			when /^\[(.*)\]$/
				group = $1
			when ''
			when /^(.*)=(.*)$/
				key = "%s.%s" % [group, $1]
				value = $2
				$config[key] = value
			end
		end

		$db_name = $config['database.path']
		$email_address = "%s <%s>" % [$config['user.name'], $config['user.primary_email']]
	end

	def vim_puts(s)
		VIM::command("echo '#{s.to_s}'")
	end

	def vim_error(s)
		VIM::command("echohl Error | echo '#{s.to_s}' | echohl None")
	end

	def vim_p(s)
		VIM::command("echo '#{s.inspect}'")
	end

	def author_filter(a)
		# TODO email format, aliases
		a.strip!
		a.gsub!(/[\.@].*/, '')
		a.gsub!(/^ext /, '')
		a.gsub!(/ \(.*\)/, '')
		a
	end

	def get_thread_id
		n = $curbuf.line_number - 1
		return "thread:%s" % $threads[n]
	end

	def get_message
		n = $curbuf.line_number
		return $messages.find { |m| n >= m.start && n <= m.end }
	end

	def get_cur_view
		if $cur_filter
			return "#{$cur_thread} and (#{$cur_filter})"
		else
			return $cur_thread
		end
	end

	def do_write
		db = Notmuch::Database.new($db_name, :mode => Notmuch::MODE_READ_WRITE)
		begin
			yield db
		ensure
			db.close
		end
	end

	def do_read
		db = Notmuch::Database.new($db_name)
		begin
			yield db
		ensure
			db.close
		end
	end

	def switch_to_prev_buffer
		$buf_queue.pop
		b = $buf_queue.last
		VIM::command("buffer #{b}") if b
	end

	def compose_unload
		b = VIM::Buffer.current
		return if b.getvar("compose_done") == 1
		compose_send if VIM::evaluate("input('[s]end/[q]uit? ')") =~ /^s/
	end

	def compose_send
		fname = VIM::evaluate("expand('%')")
		b = VIM::Buffer.current

		msg = (1..b.count).collect { |i|
			b[i]
		}.delete_if { |s|
			s.start_with? "Notmuch-Help:"
		}.drop_while { |s|
			s.empty?
		}.join("\n")

		mail = Mail.new(msg)
		sendmail = VIM::evaluate('g:notmuch_rb_sendmail')
		cmd = "%s -t -f %s" % [sendmail, mail.from.first.to_s]
		o, s = Open3.capture2e(cmd, :stdin_data => msg)
		if s.success?
			vim_puts 'Mail sent successfully.'
			vim_puts o.chomp unless o.empty?
			compose_quit
		else
			vim_error "Eeek! unable to send mail\n"
			vim_error o.chomp unless o.empty?
		end
	end

	def compose_quit
		b = VIM::Buffer.current
		b.setvar("compose_done", 1)
		b.delete!
		switch_to_prev_buffer
	end

	def open_compose_buffer(lines, start_line)
		dir = File.expand_path('~/.notmuch/compose')
		FileUtils.mkdir_p(dir)
		f = Tempfile.open(['nm-', '.mail'], dir)
		f.puts lines
		f.flush

		b = VIM::Buffer.open(f.path)
		b.setvar("compose_done", 0)
		b.setvar("&filetype", "notmuch-compose")
		b.setvar("&syntax", "notmuch-compose")
		VIM::command("call s:set_ruby_map(g:notmuch_rb_compose_maps)")
		VIM::command("autocmd BufUnload <buffer=#{b.number}> ruby compose_unload")
		b.setpos(".", start_line, 0)
		$buf_queue.push(b.number)
	end

	COMPOSE_HELP_LINES = [
		'Notmuch-Help: Type in your message here; to help you use these bindings:',
		'Notmuch-Help:   ,s    - send the message (Notmuch-Help lines will be removed)',
		'Notmuch-Help:   ,q    - abort the message',
	]

	def open_compose
		lines = []
		lines += COMPOSE_HELP_LINES
		lines << ""
		lines << "From: #$email_address"
		lines << "To: "
		lines << "Cc: #$email_address"
		lines << "Bcc: "
		lines << "Subject: "
		lines << "Reply-To: "
		lines << ""
		lines << ""
		start_line = lines.size

		sig_file = File.expand_path('~/.signature')
		if File.exists?(sig_file)
			lines << "-- "
			lines << File.readlines(sig_file)
		end

		open_compose_buffer(lines, start_line)
	end

	def open_reply(orig)
		reply = orig.reply do |m|
			# fix headers
			if not m[:reply_to]
				m.to = [orig[:from].to_s]
			end
			m.cc = [orig[:to].to_s, orig[:cc].to_s]
			m.from = $email_address
			m.charset = 'utf-8'
			m.content_transfer_encoding = '7bit'
		end

		addr = Mail::Address.new(orig[:from].value)
		name = addr.name
		name = addr.local + "@" if name.nil? && !addr.local.nil?
		name = "somebody" if name.nil?

		lines = []
		lines += COMPOSE_HELP_LINES
		lines << ""
		lines += reply.header.to_s.lines.map { |l| l.chomp }
		lines << ""
		lines << "%s wrote:" % name
		lines += orig.find_first_text.convert.lines.map { |l| "> " + l.chomp }
		lines << ""
		start_line = lines.size

		sig_file = File.expand_path('~/.signature')
		if File.exists?(sig_file)
			lines << "-- "
			lines << File.readlines(sig_file)
		end

		open_compose_buffer(lines, start_line)
	end

	def folders_render()
		$curbuf.render do |b|
			folders = VIM::evaluate('g:notmuch_rb_folders')
			count_threads = VIM::evaluate('g:notmuch_rb_folders_count_threads')
			$searches.clear
			do_read do |db|
				folders.each do |name, search|
					q = db.query(search)
					$searches << search
					count = count_threads == 0 ?
						q.search_messages.count : q.search_threads.count
					b << "%9d %-20s (%s)" % [count, name, search]
				end
			end
		end
	end

	def search_render(search)
		date_fmt = VIM::evaluate('g:notmuch_rb_date_format')
		db = Notmuch::Database.new($db_name)
		q = db.query(search)
		$threads.clear
		t = q.search_threads

		$render = $curbuf.render_staged(t) do |b, items|
			items.each do |e|
				authors = e.authors.to_utf8.split(/[,|]/).map { |a| author_filter(a) }.join(",")
				date = Time.at(e.newest_date).strftime(date_fmt)
				subject = Mail::Field.new("Subject: " + e.subject).to_s
				b << "%-12s %3s %-20.20s | %s (%s)" % [date, e.matched_messages, authors, subject, e.tags]
				$threads << e.thread_id
			end
		end
	end

	def do_tag(filter, tags)
		do_write do |db|
			q = db.query(filter)
			q.search_messages.each do |e|
				e.freeze
				tags.split.each do |t|
					case t
					when /^-(.*)/
						e.remove_tag($1)
					when /^\+(.*)/
						e.add_tag($1)
					when /^([^\+^-].*)/
						e.add_tag($1)
					end
				end
				e.thaw
				e.tags_to_maildir_flags
			end
		end
	end

	class Message
		attr_accessor :start, :body_start, :end
		attr_reader :message_id, :filename, :mail

		def initialize(msg, mail)
			@message_id = msg.message_id
			@filename = msg.filename
			@mail = mail
			@start = 0
			@end = 0
		end

		def to_s
			"id:%s" % @message_id
		end

		def inspect
			"id:%s, file:%s" % [@message_id, @filename]
		end
	end

	class StagedRender
		def initialize(buffer, enumerable, block)
			@b = buffer
			@enumerable = enumerable
			@block = block
			@last_render = 0

			@b.render { do_next }
		end

		def is_ready?
			@last_render - @b.line_number <= $curwin.height
		end

		def do_next
			items = @enumerable.take($curwin.height * 2)
			return if items.empty?
			@block.call @b, items
			@last_render = @b.count
		end
	end

	class VIM::Buffer
		def self.open(fpath)
			VIM::command("edit " + fpath)
			return VIM::Buffer.current
		end

		def <<(a)
			append(count(), a)
		end

		def render_staged(enumerable, &block)
			StagedRender.new(self, enumerable, block)
		end

		def render
			old_count = count
			yield self
			(1..old_count).each do
				delete(1)
			end
		end

		def delete!
			cmd = "bdelete! %d" % number
			VIM::command(cmd)
		end

		def getvar(varname)
			cmd = "getbufvar(%d, %p)" % [number, varname.to_str]
			VIM::evaluate(cmd)
		end

		def setvar(varname, val)
			cmd = "setbufvar(%d, %p, %p)" % [number, varname.to_str, val]
			VIM::command("call " + cmd)
			val
		end

		def setpos(expr, line, col)
			cmd = "setpos(%p, [%d, %d, %d, 0])" % [expr.to_str, number, line, col]
			VIM::command("call " + cmd)
		end
	end

	class Notmuch::Tags
		def to_s
			to_a.join(" ")
		end
	end

	class Notmuch::Message
		def to_s
			"id:%s" % message_id
		end
	end

	# workaround for bug in vim's ruby
	class Object
		def flush
		end
	end

	class Mail::Message
		def find_first_text
			return self if not multipart?
			return text_part || html_part
		end

		def convert
			if mime_type != "text/html"
				text = decoded
			else
				IO.popen("elinks --dump", "w+") do |pipe|
					pipe.write(decode_body)
					pipe.close_write
					text = pipe.read
				end
			end
			text
		end
	end

	class String
		def to_utf8
			RUBY_VERSION >= "1.9" ? force_encoding('utf-8') : self
		end
	end

	get_config
EOF
	call s:folders()
endfunction

command NotMuchR :call s:NotMuchR()

" vim: set noexpandtab:
