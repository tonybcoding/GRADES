nolist
;****************************************************************
;*                                                              *
;*     Program Name:   GRADES.ASM (Battleship simulation)       *
;*     Author:         Tony Burge                               *
;*     Purpose:        This is the final programming project    *
;*                     of CPSC 340.                             *
;*     Creation Date:  April 3, 1993                            *
;*                                                              *
;****************************************************************
hex     $

;**************************************************************

code    segment
;=========================================================================
  main          proc


		    ; //////////////////////////////////////////////////////
		    ; ///  Initialize game                               ///
		    ; //////////////////////////////////////////////////////
		    ; Set the DS register and call initialize procedure
		    mov     ax, data
		    mov     ds, ax
		    call    initialize


		    ; //////////////////////////////////////////////////////
		    ; ///  Set up playing board                          ///
		    ; //////////////////////////////////////////////////////
		    call    screen_setup


		    ; //////////////////////////////////////////////////////
		    ; ///  Initialize & establish communication link     ///
		    ; //////////////////////////////////////////////////////
		    call    comm_init


		    ; //////////////////////////////////////////////////////
		    ; ///  Begin actual game play                        ///
		    ; //////////////////////////////////////////////////////
		    ; Inform user that battle has begun
		    mov     sp_message, offset gv_begin_msg
		    mov     sp_size, size gv_begin_msg
		    call    scroll_msgmon

			; Begin main game loop
	mn_main_loop:   cmp     gv_my_turn, 'Y'
			jne     mn_not_mytrn

			; It is my turn, so attack
			call    delay_proc
			call    send_coords
			call    read_response
			mov     gv_my_turn, 'N'
			jmp     mn_analyze

			; It isn't my turn, so get attacked
	mn_not_mytrn:   call    read_coords
			call    send_response
			mov     gv_my_turn, 'Y'

			; Determine whether game is over by checking fleet
			; strength of both ally and enemy
	mn_analyze:     cmp     df_friend_str, 0
			jz      mn_we_lost
			cmp     df_enemy_str, 0
			jz      mn_we_won

			; If no one has won/lost, return to mn_main_loop
			jmp     mn_main_loop


		    ; //////////////////////////////////////////////////////
		    ; ///  End of Game.  Display win/lost status & exit  ///
		    ; //////////////////////////////////////////////////////

		    ; End of game -- We lost.
    mn_we_lost:     mov     gv_did_we_win, 'N'
		    jmp     end_program

		    ; End of game -- We Won!
    mn_we_won:      mov     gv_did_we_win, 'Y'

    end_program:    ; Run win/lose routine and exit to DOS
		    call    win_lose_proc
		    mov     ax, $4c00
		    int     $21

  main          endp
;=========================================================================
  send_coords   proc
    ; This procedure determines which coordinates to attack, and
    ; sends them.  This procedure displays coordinates sent on the
    ; message monitor.

		    ; Determine if in process of sinking a ship,
		    ; or just searching for one (use gv_strat_ptr)
		    cmp     rr_sinking_flag, 'T'
		    jne     sc_use_strat
		    jmp     sc_snkng_ship


		    ; ---------------------------------------------------
		    ; Use strategy array to attack next coordinate
		    ; ---------------------------------------------------
		    ; Move into ax the row/column info of this coordinate
		    ; and place in proper variables
    sc_use_strat:   mov     si, gv_strat_ptr
		    mov     ax, gv_strat_array [ si ]
		    mov     sc_attack_row, al
		    mov     sc_attack_col, ah

		    ; Increment the pointer into gv_strategy array to ensure
		    ; that we don't use this strategy coordinate again
		    add     gv_strat_ptr, $0002

		    ; ------------------------------------------------
		    ; Check if the coordinate has been attacked before
		    ; ------------------------------------------------
		    ; Set offset index to zero
		    mov     si, 0

			; Beginning of search loop
			; Load a word-sized value into dx at offset si
	sc_chk_loop:    mov     dx, gv_attackd_array [ si ]

			; If value in dx equals search value (ax), then
			; we've already attacked that coordinate.  Return
			; to get new strategy coordinate.
			cmp     dx, ax
			je      sc_use_strat

			; If value in dx is 'XX', then end of array has been
			; reached, and value wasn't found
			cmp     dx, 'XX'
			je      sc_good_coord

			; Increment si register by word (2) and return to loop
			add     si, 2
			jmp     sc_chk_loop

		    ; Jump to routine that sends coordinates
    sc_good_coord:  jmp     sc_send_coords


		    ; -----------------------------------------------
		    ; Use hitting algorithm to continue hitting ship
		    ; -----------------------------------------------
		    ; DO CASE Direction = 0 (search left)
    sc_snkng_ship:  cmp     rr_hit_direction, 0
		    jne     sc_snkng_right
		    dec     rr_current_col
		    jmp     sc_snkng_chk

		    ;    CASE Direction = 1 (search right)
    sc_snkng_right: cmp     rr_hit_direction, 1
		    jne     sc_snkng_up
		    inc     rr_current_col
		    jmp     sc_snkng_chk

		    ;    CASE Direction = 2 (search up)
    sc_snkng_up:    cmp     rr_hit_direction, 2
		    jne     sc_snkng_down
		    dec     rr_current_row
		    jmp     sc_snkng_chk

		    ;    OTHERWISE          (search down)
    sc_snkng_down:  inc     rr_current_row

		    ; Check new coordinates to see if they are out of range.
		    ; If so, jump to error routine
    sc_snkng_chk:   cmp     rr_current_row, "0"
		    jb      sc_snkng_error
		    cmp     rr_current_row, "7"
		    ja      sc_snkng_error
		    cmp     rr_current_col, "0"
		    jb      sc_snkng_error
		    cmp     rr_current_col, "7"
		    ja      sc_snkng_error

		    ; Check if new coords have been attacked before.  If so,
		    ; jump to error routine.  If not, they are good!  Send them!
		    ; Set offset index to zero
		    mov     si, 0
		    mov     al, rr_current_row
		    mov     ah, rr_current_col

			; Beginning of search loop
			; Load a word-sized value into dx at offset si
	sc_snkng_loop:  mov     dx, gv_attackd_array [ si ]

			; If value in dx equals search value (ax), then
			; we've already attacked that coordinate.  Jump
			; to error routine
			cmp     dx, ax
			je      sc_snkng_error

			; If value in dx is 'XX', then end of array has been
			; reached, and value wasn't found
			cmp     dx, 'XX'
			je      sc_snkng_good

			; Increment si register by word (2) and return to loop
			add     si, 2
			jmp     sc_snkng_loop

		    ; An error occured in new coordinates.  Either they
		    ; were out of range, or had already been attacked.
		    ; Increment direction flag, set current coords
		    ; equal to original coords, and try again.
    sc_snkng_error: inc     rr_hit_direction
		    mov     al, rr_orig_row
		    mov     ah, rr_orig_col
		    mov     rr_current_row, al
		    mov     rr_current_col, ah
		    jmp     sc_snkng_ship

		    ; Prepare sc_ coordinates to be sent
    sc_snkng_good:  mov     al, rr_current_row
		    mov     ah, rr_current_col
		    mov     sc_attack_row, al
		    mov     sc_attack_col, ah


		    ; ---------------------------------------------------
		    ; Send coordinates to enemy, and write row/column
		    ; info to both the "attacked array" and to the message
		    ; monitor.  Then return to calling routine.
		    ; ---------------------------------------------------

    sc_send_coords: mov     al, sc_attack_row
		    call    char_send_ack
		    mov     al, sc_attack_col
		    call    char_send_ack

		    ; Move coordinates into message at proper offset and
		    ; call message monitor
		    mov     al, sc_attack_row
		    mov     ah, sc_attack_col
		    mov     si, sc_coord_offst
		    mov     sc_attack_msg [ si ], al
		    mov     sc_attack_msg [ si + 2 ], ah
		    mov     sp_message, offset sc_attack_msg
		    mov     sp_size, size sc_attack_msg
		    call    scroll_msgmon

		    ; Move attacked coordinates into "attacked array",
		    ; and add 2 to pointer to advance it for next use
		    mov    dl, sc_attack_row
		    mov    dh, sc_attack_col
		    mov    si, gv_attackd_ptr
		    mov    gv_attackd_array [ si ], dx
		    add    gv_attackd_ptr, $0002

		    ; Return to calling routine
		    ret

  send_coords   endp
;=========================================================================
  read_response proc
    ; This procedure receives the enemy's response from our most recent
    ; attack, updates internal status variables, refreshes fleet strength,
    ; and displays appropriate message on message monitor.

		    ; Read attack response (repsonse will be placed in bl), and
		    ; setup plot_hit_miss variables
		    call    char_recv_ack
		    mov     al, sc_attack_row
		    mov     pl_row, al
		    mov     al, sc_attack_col
		    mov     pl_column, al
		    mov     pl_grid, 'E'


		    ; ---------------------------------------
		    ; If 'H' received, perform hit operations
		    ; ---------------------------------------
		    cmp     bl, 'H'
		    jne     rr_check_miss

		    ; If this is the first hit on the ship, set up
		    ; initial variables
		    cmp     rr_sinking_flag, 'F'
		    jne     rr_update_hit
		    mov     rr_sinking_flag, 'T'
		    mov     rr_hit_direction, 0
		    mov     al, sc_attack_row
		    mov     ah, sc_attack_col
		    mov     rr_orig_row, al
		    mov     rr_orig_col, ah

		    ; Update variables & call routines to plot hit and
		    ; "refresh" status bars
    rr_update_hit:  mov     rr_hit_flag, 'T'          ; Must be here in case of a previous miss
		    mov     al, sc_attack_row
		    mov     ah, sc_attack_col
		    mov     rr_current_row, al
		    mov     rr_current_col, ah
		    dec     df_enemy_str
		    call    plot_hit_miss
		    call    draw_flt_stat

		    ; Display hit message on message monitor
		    mov     sp_message, offset rr_hit_msg
		    mov     sp_size, size rr_hit_msg
		    call    scroll_msgmon

		    ; Jump to end of procedure
		    jmp     rr_exit


		    ; ----------------------------------------
		    ; If 'M' received, perform miss operations
		    ; ----------------------------------------
    rr_check_miss:  cmp     bl, 'M'
		    jne     rr_wesunkit

		    ; If a miss occurs in process of sinking a ship, jump
		    ; back to original hit and switch directions
		    cmp     rr_sinking_flag, 'T'
		    jne     rr_update_miss
		    inc     rr_hit_direction
		    mov     al, rr_orig_row
		    mov     ah, rr_orig_col
		    mov     rr_current_row, al
		    mov     rr_current_col, ah

		    ; Update variables & call routine to plot miss
    rr_update_miss: mov     rr_hit_flag, 'F'
		    call    plot_hit_miss

		    ; Display miss message on message monitor
		    mov     sp_message, offset rr_miss_msg
		    mov     sp_size, size rr_miss_msg
		    call    scroll_msgmon

		    ; Jump to end of procedure
		    jmp     rr_exit


		    ; ----------------------------------------
		    ; If 'S' received, perform sink operations
		    ; ----------------------------------------
    rr_wesunkit:    cmp     bl, 'S'
		    jne     rr_error

		    ; Beep, update variables, call routine to plot sink,
		    ; and refresh fleet strenght grid
		    mov     ah, $02
		    mov     dl, $07
		    int     $21
		    mov     rr_hit_flag, 'F'
		    mov     rr_sinking_flag, 'F'
		    dec     df_enemy_ships
		    dec     df_enemy_str
		    call    draw_flt_stat
		    call    plot_hit_miss

		    ; Display sink message on message monitor
		    mov     sp_message, offset rr_sink_msg
		    mov     sp_size, size rr_sink_msg
		    call    scroll_msgmon

		    ; Jump to end of procedure
		    jmp     rr_exit


		    ; -------------------------------------------------------
		    ; If 'H', 'M', or 'S' not received, then an error occured
		    ; -------------------------------------------------------
    rr_error:       mov     si, rr_error_offst
		    mov     rr_error_msg [ si ], bl
		    mov     sp_message, offset rr_error_msg
		    mov     sp_size, size rr_error_msg
		    call    scroll_msgmon


		    ; -------------------------
		    ; Return to calling routine
		    ; -------------------------
    rr_exit:        ret

  read_response endp
;=========================================================================
  read_coords   proc
    ; This procedure receives the enemy's attack coordinates
    ; INPUT:

		    ; Read attack coordinates from comport 1
		    call    char_recv_ack
		    mov     rc_our_row, bl
		    call    char_recv_ack
		    mov     rc_our_column, bl

		    ; Display attacked coordinates on message monitor
		    mov     al, rc_our_row
		    mov     si, rc_coord_offst
		    mov     rc_attack_msg [ si ], al
		    mov     al, rc_our_column
		    mov     rc_attack_msg [ si + 2 ], al

		    ; Call message monitor
		    mov     sp_message, offset rc_attack_msg
		    mov     sp_size, size rc_attack_msg
		    call    scroll_msgmon

		    ; Return to calling routine
		    ret

  read_coords   endp
;=========================================================================
  send_response proc
    ; This procedure determines whether coordinates received hit, missed,
    ; or sank one of our ships.
    ; INPUT:  rc_our_row, rc_our_column (both which have been set by
    ;         read_coords

		    ; Set up variabls for plot procedure
		    mov     al, rc_our_row
		    mov     pl_row, al
		    mov     ah, rc_our_column
		    mov     pl_column, ah
		    mov     pl_grid, 'A'

		    ; -------------------------------------------
		    ; Check if the coordinate received hit a ship
		    ; Set offset index to zero
		    ; -------------------------------------------
		    mov     si, 0

			; Beginning of search loop.  Load a word-sized
			; value from ship array into dx at offset si
	sr_chk_loop:    mov     dx, gv_ally_array [ si ]

			; If value in dx equals search value (ax), then
			; the coordinate was a hit or sink
			cmp     dx, ax
			je      sr_hitorsunk

			; If value in dx is 'XX', then end of array has been
			; reached, and value wasn't found; therefore, a miss
			cmp     dx, 'XX'
			je      sr_missed_me

			; Increment si register by word (2) and return to loop
			add     si, 2
			jmp     sr_chk_loop


		    ; ------------------------------------------
		    ; The enemy's shot was a MISS, so inform him
		    ; ------------------------------------------
		    ; Send 'M' through comport 1
    sr_missed_me:   mov     al, 'M'
		    call    char_send_ack

		    ; Display miss message on message monitor
		    mov     sp_message, offset sr_miss_msg
		    mov     sp_size, size sr_miss_msg
		    call    scroll_msgmon
		    mov     bl, 'M'
		    jmp     sr_exit


		    ; ---------------------------------------------
		    ; The enemy's shot HIT, so determine if it sunk
		    ; a ship and inform enemy.
		    ; ---------------------------------------------
		    ; Replace hit coordinates with 'HH'.  This enables us
		    ; to check if ship was hit
    sr_hitorsunk:   mov     ax, 'HH'
		    mov     gv_ally_array [ si ], ax

		    ; Go to the left until 'EE' is reached if only HH's in between,
		    ; then search right.  If coordinates are found, ship wasn't sunk
		    ; only hit.
		    ; Preserve originial array location
		    mov     sr_array_loc, si
		    sub     si, 2

	sr_leftHH_loop: mov     dx, gv_ally_array [ si ]

			; If value in dx is 'EE', then left end of ship has been
			; reached.  Try searching right.
			cmp     dx, 'EE'
			je      sr_chk_right

			; If value in dx doesn't equal "HH", then
			; ship has not been sunk
			cmp     dx, 'HH'
			jne     sr_hit_me

			; Increment si register by word (2) and return to loop
			sub     si, 2
			jmp     sr_leftHH_loop


		    ; Go to the right until 'EE' is reached if only HH's in between,
		    ; then the ship was sunk.  If coordinates are found, ship was
		    ; hit, and not sunk.
		    ; Restore original array location of hit coordinate
    sr_chk_right:   mov     si, sr_array_loc
		    add     si, 2

	sr_rghtHH_loop: mov     dx, gv_ally_array [ si ]

			; If value in dx is 'EE', then right end of ship has been
			; reached, and ship has been sunk.
			cmp     dx, 'EE'
			je      sr_sunk_me

			; If value in dx doesn't equal "HH", then
			; ship has not been sunk
			cmp     dx, 'HH'
			jne     sr_hit_me

			; Increment si register by word (2) and return to loop
			add     si, 2
			jmp     sr_rghtHH_loop

		    ; Beep and prepare variables for calls to char_send_ack
		    ; and scroll_msgmon
    sr_sunk_me:     dec     df_friend_ships
		    mov     ah, $02
		    mov     dl, $07
		    int     $21
		    mov     al, 'S'
		    mov     sp_message, offset sr_sink_msg
		    mov     sp_size, size sr_sink_msg
		    jmp     sr_hitsinkdisp

		    ; Prepare variables for calls to char_send_ack and scroll_msgmon
    sr_hit_me:      mov     al, 'H'
		    mov     sp_message, offset sr_hit_msg
		    mov     sp_size, size sr_hit_msg

		    ; Send 'H' or 'S' to enemy and display message on message monitor
    sr_hitsinkdisp:
		    call    char_send_ack
		    call    scroll_msgmon

		    ; "Refresh" strength status bars
		    dec     df_friend_str
		    call    draw_flt_stat
		    mov     bl, 'H'

		    ; -------------------------
		    ; Return to calling routine
		    ; -------------------------
    sr_exit:        call    plot_hit_miss
		    ret

  send_response endp
;=========================================================================
  win_lose_proc proc
    ; This procedure flashed the grid of the winner, display message to
    ; hit any key to exit, and clears screen

		    ; Set up base row/column of appropriate grid
		    cmp     gv_did_we_win, 'Y'
		    jne     wl_enemy_grid

		    ; Coordinates & messages for ally grid
		    mov     sp_message, offset wl_won_msg1
		    mov     sp_size, size wl_won_msg1
		    call    scroll_msgmon
		    mov     sp_message, offset wl_won_msg2
		    mov     sp_size, size wl_won_msg2
		    call    scroll_msgmon
		    mov     sp_message, offset wl_line_msg
		    mov     sp_size, size wl_line_msg
		    call    scroll_msgmon
		    mov     wl_row, 0
		    mov     wl_column, 3
		    add     wl_column, 33
		    jmp     wl_flash_grid

		    ; Coordinates & messages for enemy grid
    wl_enemy_grid:  mov     sp_message, offset wl_lost_msg1
		    mov     sp_size, size wl_lost_msg1
		    call    scroll_msgmon
		    mov     sp_message, offset wl_lost_msg2
		    mov     sp_size, size wl_lost_msg2
		    call    scroll_msgmon
		    mov     sp_message, offset wl_line_msg
		    mov     sp_size, size wl_line_msg
		    call    scroll_msgmon
		    mov     wl_row, 0
		    mov     wl_column, 44
		    add     wl_column, 33             ; This is necessary do to initial subtraction of 33

		    ; This loop goes down each row
    wl_flash_grid:  mov     cx, 18                    ; Number of rows

			; This loop goes across each column in the row
	wl_row_loop:    push    cx
			mov     cx, 33                ; Number of columns
			sub     wl_column, 33

	    wl_col_loop:    push    cx
			    mov     dh, wl_row
			    mov     dl, wl_column
			    call    position_crs
			    mov     ah, $08           ; Get current character (al)
			    mov     bh, video_page    ; and attribute (ah)
			    int     $10
			    or      ah, 10000000B     ; Turn on blinking attribute
			    mov     bl, ah
			    call    print_char        ; Redisplays same character blinking

			    ; Increment the column, retrieve the counter and loop
			    ; if cx doesn't equal zero
			    inc     wl_column
			    pop     cx
			    loop    wl_col_loop

			; Increment the row, retrieve the counter and loop
			; if cx doesn't equal zero
			inc     wl_row
			pop     cx
			loop    wl_row_loop

		    ; -----------------------------------------------
		    ; Display Hit any key to exit prompt.
		    ; -----------------------------------------------
		    mov     sp_message, offset wl_hitkey_msg
		    mov     sp_size, size wl_hitkey_msg
		    call    scroll_msgmon

		    ; Read keyboard without echo
		    mov     ah, $0c
		    mov     al, $08
		    int     $21

		    ; Clear screen and return to calling routine
		    call    clear_screen
		    mov     sp_row, 1
		    mov     sp_column, 0
		    mov     sp_message, offset wl_byebye_msg
		    mov     sp_size, size wl_byebye_msg
		    mov     sp_color, 00001010B       ; Lt Green on black
		    call    string_print
		    mov     dh, 3
		    mov     dl, 0
		    call    position_crs
		    ret

  win_lose_proc endp
;=========================================================================
  initialize    proc
    ; This procedure displays the introduction screen, asks
    ; the user whether he attacks first or not, and asks for the
    ; delay time.
    ; INPUT:  none

		    ; Clear screen and store current video page
		    ; in video_page variable
		    call    clear_screen
		    mov     ah, $0f
		    int     $10
		    mov     video_page, bh


		    ; ////////////////////////////////
		    ; ///  Display Grid and title  ///
		    ; ////////////////////////////////
		    ; Paint full screen red
		    mov     sp_message, offset in_full_line
		    mov     sp_size, size in_full_line
		    mov     sp_color, 01000100B       ; Red on red
		    mov     sp_row, 0
		    mov     cx, 25

			; Loop to print 25 red lines
	in_screen_red:  push    cx
			mov     sp_column, 0
			call    string_print
			inc     sp_row
			pop     cx
			loop    in_screen_red

		    ; Print series of grid lines in top, left corner
		    mov     sp_color, 00010111B       ; White on blue
		    mov     sp_row, 0
	in_box_loop:    mov     sp_column, 0
			mov     sp_message, offset ss_mid2_grid
			mov     sp_size, ss_mid2_grid_size
			add     sp_message, 3
			sub     sp_size, 3
			call    string_print
			inc     sp_row
			mov     sp_column, 0
			mov     sp_message, offset ss_mid1_grid
			mov     sp_size, ss_mid1_grid_size
			add     sp_message, 3
			sub     sp_size, 3
			call    string_print
			inc     sp_row
			cmp     sp_row, 10
			jne     in_box_loop

		    ; Print bottom grid line
		    mov     sp_row, 10
		    mov     sp_column, 0
		    mov     sp_message, offset ss_bot_grid
		    mov     sp_size, ss_bot_grid_size
		    add     sp_message, 3
		    sub     sp_size, 3
		    call    string_print

		    ; Print right shadow down grid
		    mov     sp_message, offset in_space
		    mov     sp_size, size in_space
		    mov     sp_color, 00000000B       ; Gray on red
		    mov     sp_row, 0

	in_right_shad:  mov     sp_column, 30
			call    string_print
			inc     sp_row
			cmp     sp_row, 12
			jne     in_right_shad

		    ; Print bottom shadow under grid
		    mov     sp_row, 11
		    mov     sp_column, 0

	in_bott_shad:   call    string_print
			cmp     sp_column, 31
			jne     in_bott_shad


		    ; //////////////////////////////////
		    ; ///  Display text and prompts  ///
		    ; //////////////////////////////////

		    ; Display title G.R.A.D.E.S.
		    mov     sp_row, 5
		    mov     sp_column, 4
		    mov     sp_message, offset in_title_ln1
		    mov     sp_size, size in_title_ln1
		    mov     sp_color, 00011111B       ; Bright white on blue
		    call    string_print

		    ; Display six secondary titles
		    mov     sp_row, 0
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln2
		    mov     sp_size, size in_title_ln2
		    mov     sp_color, 01000111B      ; White on red
		    call    string_print

		    add     sp_row, 2
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln3
		    mov     sp_size, size in_title_ln3
		    call    string_print

		    add     sp_row, 2
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln4
		    mov     sp_size, size in_title_ln4
		    call    string_print

		    add     sp_row, 2
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln5
		    mov     sp_size, size in_title_ln5
		    call    string_print

		    add     sp_row, 2
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln6
		    mov     sp_size, size in_title_ln6
		    call    string_print

		    add     sp_row, 2
		    mov     sp_column, 33
		    mov     sp_message, offset in_title_ln7
		    mov     sp_size, size in_title_ln7
		    call    string_print

		    mov     sp_row, 6
		    mov     sp_column, 3
		    mov     sp_color, 00010111B       ; White on blue
		    mov     sp_message, offset in_title_ln8
		    mov     sp_size, size in_title_ln8
		    call    string_print

		    ; Display slashes in front of prompts
		    mov     sp_color, 01000000B       ; Black on red
		    mov     sp_row, 20
		    mov     sp_message, offset in_slash
		    mov     sp_size, size in_slash
		    mov     cx, 1
    in_draw_slash:  push    cx
		    mov     sp_column, 20
		    add     sp_column, cl
		    call    string_print
		    add     sp_message, 2
		    sub     sp_size, 2
		    inc     sp_row
		    pop     cx
		    add     cx, 2
		    cmp     cx, 9
		    jne     in_draw_slash

		    ; ------------------------------------
		    ; Display title prompt 1 and get input
		    ; ------------------------------------
    initprompt1:    mov     sp_column, 30
		    mov     sp_row, 21
		    mov     sp_message, offset in_title_prompt1
		    mov     sp_size, size in_title_prompt1
		    mov     sp_color, 01000000B       ; Black on red
		    call    string_print

		    mov     ah, $0c                   ; clear keyboard buffer
		    mov     al, $08                   ; keyboard input without echo
		    int     $21
		    mov     delay, al

		    ; Ensure delay is a value in the ranges of 0 - 9
		    cmp      delay, $30
		    jb       bad_initprmpt1
		    cmp      delay, $39
		    ja       bad_initprmpt1
		    jmp      in_conv_delay

		    ; If the user entered out of the range, beep
		    ; and prompt again.
    bad_initprmpt1: mov     ah, $02
		    mov     dl, $07
		    int     $21
		    jmp     initprompt1

		    ; Convert ASCII value of delay to decimal
    in_conv_delay:  sub     delay, $30

		    ; ------------------------------------
		    ; Display title prompt 2 and get input
		    ; ------------------------------------
    initprompt2:    mov     sp_column, 30
		    mov     sp_row, 22
		    mov     sp_message, offset in_title_prompt2
		    mov     sp_size, size in_title_prompt2
		    call    string_print

		    mov     ah, $0c                   ; clear keyboard buffer
		    mov     al, $08                   ; keyboard input without echo
		    int     $21
		    mov     gv_my_turn, al

		    ; convert entry to upper case and ensure user entered only Y or N
		    cmp     gv_my_turn, $5a
		    jb      chkattackfirst
		    sub     gv_my_turn, $20

		    ; see if user entered 'Y'
    chkattackfirst: cmp     gv_my_turn, 'Y'
		    je      end_init

		    ; see if user entered 'N'
		    cmp     gv_my_turn, 'N'
		    je      end_init

		    ; If the user didn't enter a 'Y' or 'N', beep and
		    ; prompt again.
		    mov     ah, $02
		    mov     dl, $07
		    int     $21
		    jmp     initprompt2


		    ; ////////////////////////////////////
		    ; ///  Return to calling routine.  ///
		    ; ////////////////////////////////////
    end_init:       ret

  initialize    endp
;=========================================================================
  comm_init     proc
    ; This procedure initializes and establishes communication
    ; between the two connected PC's by sending an 'X' to show
    ; that it's ready until an 'X' or 'A' is received from the
    ; other PC.
    ; INPUT:  none

		    ; Inform user that initialization has begun
		    mov     sp_message, offset ci_start_msg
		    mov     sp_size, size ci_start_msg
		    call    scroll_msgmon

		    ; Initialize comport function (al=1200 baud, no
		    ; parity, 1 stop bit, 8-bit word; dx=comport 1)
		    mov     ah, $00
		    mov     al, 10000011B
		    mov     dx, 0
		    int     $14

			; Send 'X' to other PC via comport 1
	ci_loop:        mov     al, 'X'
			mov     ah, 01
			mov     dx, 0
			int     $14

			; Read character from comport 1
			mov     al, 0
			mov     ah, 02
			mov     dx, 0
			int     $14

			; If character received is 'X', jump to
			; send acknowledge
			cmp     al, 'X'
			je      ci_send_ack

			; If not 'X' or 'A', go through loop again
			cmp     al, 'A'
			jne     ci_loop

		    ; If character received is 'A', send 'A' back
		    ; and exit
		    call    char_send
		    jmp     ci_exit

		    ; If character received is 'X', send 'A' back and
		    ; wait for acknowledgement
    ci_send_ack:    mov     al, 'A'
		    call    char_send

			; Inner loop to wait for 'A'cknowledge
	ci_wait_for_A:  call    char_recv
			cmp     al, 'A'
			jne     ci_wait_for_A

		    ; Inform user that operation is complete, and
		    ; return to calling routine.
    ci_exit:        mov     sp_message, offset ci_finish_msg
		    mov     sp_size, size ci_finish_msg
		    call    scroll_msgmon
		    ret

  comm_init     endp
;=========================================================================
  char_send     proc
    ; This procedure sends 1 character via comport 1.  If an error occurs,
    ; it continually retransmits the character.  However, this procedure
    ; does not wait for an acknowledge.
    ; INPUT:  al (the character to send)

		    ; Send character in al by BIOS interrupt $14,
		    ; subfunction $01
    cs_send_loop:   mov     ah, 01
		    mov     dx, 0
		    int     $14

		    ; Check if error occured.  If so, go back to send loop
		    and     ah, $80
		    jnz     cs_send_loop

		    ; Return to calling routine
		    ret

  char_send     endp
;=========================================================================
  char_send_ack proc
    ; This procedure sends 1 character via comport 1 AND waits for an
    ; acknowledge from the receiving PC.
    ; INPUT:  al (the character to send)

		    ; Send character in al by BIOS interrupt $14,
		    ; subfunction $01
    sa_send_loop:   mov     ah, 01
		    mov     dx, 0
		    int     $14

		    ; Check if error occured.  If so, go back to send loop
		    and     ah, $80
		    jnz     sa_send_loop

		    ; If no send error occured, recieve a character.
		    ; If 'A' received, then operation went well, exit.
		    call    char_recv
		    cmp     al, 'A'
		    je      sa_send_ackd

		    ; If wasn't received, display error message on
		    ; message monitor
		    mov     sp_message, offset sa_send_error
		    mov     sp_size, size sa_send_error
		    call    scroll_msgmon

		    ; Return to calling routine
    sa_send_ackd:   ret

  char_send_ack endp
;=========================================================================
  char_recv     proc
    ; This procedure waits and receives 1 character from comport 1.  The
    ; character is returned in al
    ; INPUT:  none

		    ; Read character to al by BIOS interrupt $14,
		    ; subfunction $02
    cr_read_loop:   mov     ah, 02
		    mov     dx, 0
		    int     $14

		    ; Check if error occured.  If so, go back to recv loop
		    and     ah, $80
		    jnz     cr_read_loop

		    ; Return to calling routine
		    ret

  char_recv     endp
;=========================================================================
  char_recv_ack proc
    ; This procedure receives 1 character from comport 1 AND sends
    ; acknowledge back to sending PC.
    ; INPUT:  none
    ; OUTPUT:  bl (the character received)

		    ; Receive character in al by BIOS interrupt $14,
		    ; subfunction $02
    sa_recv_loop:   mov     ah, 02
		    mov     dx, 0
		    int     $14

		    ; Check if error occured.  If so, go back to recv loop
		    and     ah, $80
		    jnz     sa_recv_loop

		    ; Transfer al to bl and send acknowledge
		    mov     bl, al
		    mov     al, 'A'
		    call    char_send

		    ; Return to calling routine
		    ret

  char_recv_ack endp
;=========================================================================
  screen_setup  proc
    ; This procedures displays the main playing board of the game.

		    ; Clear screen
		    call    clear_screen


		    ; ///////////////////
		    ; ///  Draw Text  ///
		    ; ///////////////////

		    ; Allied/Enemy fleet text
		    mov     sp_row, 0
		    mov     sp_column, 3
		    mov     sp_message, offset ss_allied_text
		    mov     sp_size, size ss_allied_text
		    mov     sp_color, 00010111B       ; White on blue
		    call    string_print
		    mov     sp_column, 44
		    mov     sp_message, offset ss_enemy_text
		    mov     sp_size, size ss_enemy_text
		    mov     sp_color, 01000111B       ; White on red
		    call    string_print

		    ; Force Strength text
		    mov     sp_row, 21
		    mov     sp_column, 2
		    mov     sp_message, offset ss_text2
		    mov     sp_size, size ss_text2
		    mov     sp_color, 00000010B       ; Green on black
		    call    string_print


		    ; ////////////////////
		    ; ///  Draw grids  ///
		    ; ////////////////////
		    mov     ss_column, 3
		    mov     al, ss_frnd_grid_col
		    mov     sp_color, al

			; Draw top line of current grid.  This loop draws
			; both allied and enemy grids
	ss_grid1_loop:  mov     sp_row, 1
			mov     al, ss_column
			mov     sp_column, al
			mov     sp_message, offset ss_top_grid
			mov     sp_size, ss_top_grid_size
			call    string_print

			; Display 8 sets of middle lines
			mov     ss_row, 2

	    ss_grid2_loop:  ; Draw middle line one.  This loop draws all
			    ; middle lines of current grid (allied/enemy)
			    mov     al, ss_row
			    mov     sp_row, al
			    mov     al, ss_column
			    mov     sp_column, al
			    mov     sp_message, offset ss_mid1_grid
			    mov     sp_size, ss_mid1_grid_size
			    call    string_print

			    ; Draw middle line two
			    inc    sp_row
			    mov    al, ss_column
			    mov    sp_column, al
			    mov    sp_message, offset ss_mid2_grid
			    mov    sp_size, ss_mid2_grid_size
			    call   string_print

			    ; Continue printing middle lines until 8 sets
			    ; have been printed
			    add    ss_row, 2
			    cmp    ss_row, 18
			    jne    ss_grid2_loop

			; Draw bottom line
			mov     al, ss_column
			mov     sp_column, al
			mov     sp_message, offset ss_bot_grid
			mov     sp_size, ss_bot_grid_size
			call    string_print

			; Draw shadow on bottom
			inc     sp_row
			mov     al, ss_column
			inc     al
			mov     sp_column, al
			mov     sp_message, offset ss_bot_shadow
			mov     sp_size, size ss_bot_shadow
			mov     sp_color, 00001000B   ; Gray on black
			call    string_print

			; This loop is only to be repeated twice by
			; checking for column count over 80.  Also,
			; grid color is changed.
			add     ss_column, 41
			cmp     ss_column, 80
			mov     al, ss_enem_grid_col
			mov     sp_color, al
			ja      ss_shadow_draw
			jmp     ss_grid1_loop

			; Draw shadow down side of grids
    ss_shadow_draw:     mov     sp_message, offset ss_side_shadow
			mov     sp_size, size ss_side_shadow
			mov     sp_color, 00001000B   ; Gray on black
			mov     sp_row, 1
			mov     sp_column, 36
			mov     cx, 17                ; Set counter for 17 lines
	 ss_shadow_loop:    push    cx
			    call    string_print
			    add     sp_column, 40
			    call    string_print
			    sub     sp_column, 42
			    inc     sp_row
			    pop     cx
			    loop    ss_shadow_loop


		    ; //////////////////////////
		    ; ///  Draw Status Bars  ///
		    ; //////////////////////////

		    mov     ss_column, 0
		    mov     al, 00001110B             ; Yellow on black
		    mov     sp_color, al

			; Draw top line of current status bar.  This loop
			; draws both allied and enemy status boxes.
	ss_stat_loop:   mov    sp_row, 22
			mov    al, ss_column
			mov    sp_column, al
			mov    sp_message, offset ss_top_statbar
			mov    sp_size, size ss_top_statbar
			call   string_print

			; Draw middle line of current status bar
			mov    sp_row, 23
			mov    al, ss_column
			mov    sp_column, al
			mov    sp_message, offset ss_mid_statbar
			mov    sp_size, size ss_mid_statbar
			call   string_print

			; Draw bottom line of current status bar
			mov    sp_row, 24
			mov    al, ss_column
			mov    sp_column, al
			mov    sp_message, offset ss_bot_statbar
			mov    sp_size, size ss_bot_statbar
			call   string_print

			; This loop is only to be repeated twice by
			; checking for column count over 80.  Also,
			; grid color is changed.
			add     ss_column, 61
			cmp     ss_column, 80
			ja      ss_draw_redbar
			jmp     ss_stat_loop

		    ; Call procedure to "refresh" actual status bar
    ss_draw_redbar: call    draw_flt_stat


		    ; //////////////////////////////
		    ; ///  Draw Message Monitor  ///
		    ; //////////////////////////////

		    mov     al, sm_msgtxt_col
		    mov     sp_color, al

		    ; Draw top line of message monitor
		    mov     sp_column, 21
		    mov     sp_row, 19
		    mov     sp_message, offset ss_top_msgmon
		    mov     sp_size, size ss_top_msgmon
		    call    string_print

			; Loop to draw 4 middle lines
	ss_msgmonloop:  inc     sp_row
			mov     sp_column, 21
			mov     sp_message, offset ss_mid_msgmon
			mov     sp_size, size ss_mid_msgmon
			call    string_print

			; If 23rd column not printed, return to loop
			cmp     sp_row, 23
			jne     ss_msgmonloop

		    ; Draw bottom line of message monitor
		    mov     sp_column, 21
		    inc     sp_row
		    mov     sp_message, offset ss_bot_msgmon
		    mov     sp_size, size ss_bot_msgmon
		    call    string_print


		    ; /////////////////////////////
		    ; ///  Draw Friendly Ships  ///
		    ; /////////////////////////////
		    ; coordinates given in (row, column) format

		    ; Draw first ship (horizontal)
		    ; (0,2) (0,3)
		    mov     ds_begin_row, 2
		    mov     ds_begin_col, 12
		    mov     ds_ship_length, 2
		    mov     ds_ship_direct, 1
		    call    draw_ship

		    ; Draw second ship (horizontal)
		    ; (1,5) (1,6) (1,7)
		    mov     ds_begin_row, 4
		    mov     ds_begin_col, 24
		    mov     ds_ship_length, 3
		    mov     ds_ship_direct, 1
		    call    draw_ship

		    ; Draw third ship (horizontal)
		    ; (6,1) (6,2) (6,3) (6,4)
		    mov     ds_begin_row, 14
		    mov     ds_begin_col, 8
		    mov     ds_ship_length, 4
		    mov     ds_ship_direct, 1
		    call    draw_ship

		    ; Draw fourth ship (vertical)
		    ; (2,6) (3,6) (4,6) (5,6) (6,6)
		    mov     ds_begin_row, 6
		    mov     ds_begin_col, 28
		    mov     ds_ship_length, 5
		    mov     ds_ship_direct, 0
		    call    draw_ship

		    ; Draw fifth ship (vertical)
		    ; (3,0) (4,0) (5,0)
		    mov     ds_begin_row, 8
		    mov     ds_begin_col, 4
		    mov     ds_ship_length, 3
		    mov     ds_ship_direct, 0
		    call    draw_ship


		    ; ///////////////////////////////////
		    ; ///  Return to calling routine  ///
		    ; ///////////////////////////////////
		    ret

  screen_setup  endp
  ;-----------------------------------------------------------------------
      draw_ship     proc
	; This is a subprocedure of screen_setup, and itdraws ships on
	; the screen given the proper beginning row/column, length,
	; and direction
	; INPUT:  ds_begin_row, ds_begin_col, ds_ship_length (2,3,4,5),
	;         ds_ship_direct ("0"=vertical, "1"=horizontal)

			; determine direction of ship
			cmp     ds_ship_direct, 0
			je      ds_vertical
			jmp     ds_horizontal


			; ////////////////////////////
			; ///  Draw Vertical Ship  ///
			; ////////////////////////////
			; Convert ds_ship length to proper value
			; Actual length determined by following formula
			; length = ((ds_ship_length * 2) - 1)
	ds_vertical:    mov     al, ds_ship_length
			mov     ah, 0
			mov     bl, 2
			mul     bl
			dec     al
			mov     cl, al
			mov     ch, 0
			mov     al, ds_ship_color
			mov     sp_color, al

			    ; Loop to draw ship beginning at row/column parameter
			    ; Position cursor at first location
	    ds_vert_loop:   mov     al, ds_begin_row
			    mov     sp_row, al
			    mov     al, ds_begin_col
			    mov     sp_column, al
			    mov     sp_message, offset ds_ship_chars
			    mov     sp_size, size ds_ship_chars
			    push    cx                    ; preserve the counter
			    call    string_print
			    pop     cx

			    ; Loop until CX=0 (length)
			    inc     ds_begin_row
			    loop    ds_vert_loop


			jmp     end_draw_ship


			; //////////////////////////////
			; ///  Draw Horizontal Ship  ///
			; //////////////////////////////

			; Convert ds_ship_length to proper value
			; Actual length determined by following formula
			; length = ((ds_ship_length * 4) -1))
	ds_horizontal:  mov     al, ds_ship_length
			mov     ah, 0
			mov     bl, 4
			mul     bl
			dec     al
			mov     cl, al
			mov     ch, 0

			    ; Loop to draw ship beginning at row/column parameters
			    ; Position cursor at first location
	    ds_hrznt_loop:  mov     dh, ds_begin_row
			    mov     dl, ds_begin_col
			    call    position_crs

			    ; Print ship character at current location
			    push    cx
			    mov     bl, ds_ship_color
			    mov     al, $b0
			    call    print_char
			    pop     cx

			    ; Loop until CX = 0 (length)
			    inc     ds_begin_col
			    loop    ds_hrznt_loop

			; -------------------------
			; Return to calling routine
			; -------------------------
	end_draw_ship:  ret

      draw_ship     endp
  ;-----------------------------------------------------------------------
;=========================================================================
  clear_screen  proc
    ; This procedure clears the video screen by calling BIOS
    ; function $10, subfunction $0f to get the current video
    ; mode (in AL), and then "resets" to the same mode with
    ; function $10, subfuntion $00.  This function maintains the
    ; integrity of the AX and BP registers.
    ; INPUT:  none.

		    push    ax
		    push    bp
		    mov     ah, $0f
		    int     $10
		    mov     ah, $00
		    int     $10
		    pop     bp
		    pop     ax
		    ret

  clear_screen  endp
;=========================================================================
  scroll_msgmon proc
    ; This procedure scrolls the information in message monitor
    ; up one row, and displays the new text
    ; INPUT:  sp_message and sp_size should already be set.

		    ; Scroll current text up one row
		    mov     ah, $06
		    mov     al, 1
		    mov     bh, sm_msgtxt_col
		    mov     ch, 20
		    mov     cl, 22
		    mov     dh, 23
		    mov     dl, 57
		    int     $10

		    ; Print new text on bottom line
		    mov     sp_row, 23
		    mov     sp_column, 22
		    mov     al, sm_msgtxt_col
		    mov     sp_color, al
		    call    string_print

		    ; Return to calling routine
		    ret

  scroll_msgmon endp
;=========================================================================
  position_crs  proc
    ; This procedure sets the next cursor position to the values
    ; held in dh, dl.
    ; INPUT:  dh (row), dl (column)

		    mov     ah, $02                   ; Set ah to subfunction $02
		    mov     bh, video_page            ; Set bh to current video page
		    int     $10
		    ret

  position_crs  endp
;=========================================================================
  print_char    proc
    ; This procedure prints character {al} at the current cursor
    ; location with {bl} attributes.
    ; INPUT:  al, bl

		    mov     ah, $09
		    mov     bh, video_page
		    mov     cx, 1
		    int     $10
		    ret

  print_char    endp
;=========================================================================
  delay_proc    proc
    ; This procedure delays processing for {delay} seconds
    ; INPUT:  none

		    ; If the delay is zero seconds, exit procedure
		    cmp     delay, 0
		    je      end_delay_proc
		    mov     bl, delay

		    ; This is necessary, because the first time
		    ; through delay_loop will immediately decrement it
		    ; since dh wasn't equal to seconds before being
		    ; assigned to de_old_second
		    inc     bl

    delay_loop:     ; Stay in this loop until second changes
		    mov     de_old_second, dh
		    mov     ah, $2c
		    int     $21
		    cmp     dh, de_old_second
		    je      delay_loop

		    ; Return to delay_loop until bl (delay) = zero
		    dec     bl
		    jnz     delay_loop

    end_delay_proc: ; Return to calling routine
		    ret

  delay_proc    endp
;=========================================================================
  string_print  proc
    ; This procedure prints an entire string array with the specified
    ; attributes at the specified location.
    ; INPUT:  sp_size, sp_column, sp_row, sp_message, sp_color

		    ; set up counter and index
		    mov     cx, sp_size
		    mov     si, sp_message            ; offset calc'd in calling routine

    sp_loop:        ; position cursor to desired position
		    mov     dh, sp_row
		    mov     dl, sp_column
		    call    position_crs

		    ; Print character at index SI
		    push    cx
		    mov     ah, $09
		    mov     al, [ si ]
		    mov     bh, video_page
		    mov     bl, sp_color
		    mov     cx, 1
		    int     $10
		    pop     cx


		    ; increment SI and return to loop if sp_size not zero
		    inc     sp_column                 ; move one space to the right
		    inc     si
		    loop    sp_loop

		    ret

  string_print  endp
;=========================================================================
  draw_flt_stat proc
    ; This procedure "refreshes" the fleet status bar of both
    ; ally and enemy fleets
    ; INPUT:  none.

		    ; Plot number of ships on top line
		    mov     sp_row, 0
		    mov     sp_color, 00011111B       ; Br. White on blue
		    mov     sp_message, offset df_friend_ships
		    mov     sp_size, size df_friend_ships
		    mov     sp_column, 24
		    call    string_print

		    mov     sp_color, 01001111B       ; Br. White on red
		    mov     sp_message, offset df_enemy_ships
		    mov     sp_size, size df_enemy_ships
		    mov     sp_column, 64
		    call    string_print

		    ; Set finished flag to false "0"
		    mov     df_finished_flg, 0

		    ; Prepare counter and generic variables for "ally"
		    ; stat bar.
		    mov     cl, df_friend_str
		    mov     df_generic_str, cl
		    mov     ch, 0
		    mov     al, df_friend_col
		    mov     df_generic_col, al

			; --------------------
			; Loop to draw red bar
			; --------------------
	df_redbar_loop: ; If df_generic_str = 0, then jump to print "empty" portion
			cmp     df_generic_str, 0
			je      df_exit_redbar

			; Position cursor to proper location
			mov     dh, 23
			mov     dl, df_generic_col
			call    position_crs

			; Print status character at current location
			push    cx
			mov     bl, 00000100B
			mov     al, $db
			call    print_char
			pop     cx

			; Loop until CX = 0 (red part of bar)
			inc     df_generic_col
			loop    df_redbar_loop

		    ; Subtract 17 from df_generic_str to see
		    ; black space to print after bar.  If zero,
		    ; then this bar is finished
  df_exit_redbar:   mov     ch, 0
		    mov     cl, 17
		    sub     cl, df_generic_str
		    jz      end_draw_loop

			; ----------------------------------------
			; Loop to draw "empty" space at end of bar
			; ----------------------------------------
	df_blkbar_loop: mov    dh, 23
			mov    dl, df_generic_col
			call   position_crs

			; Print "blank" character at current location
			push    cx
			mov     bl, 00000000B
			mov     al, $db
			call    print_char
			pop     cx

			; Loop until CX = 0 (empty part of bar)
			inc     df_generic_col
			loop    df_blkbar_loop


		    ; Change counter and variables to reflect "enemy"
		    ; stat bar
    end_draw_loop:  mov     cl, df_enemy_str
		    mov     df_generic_str, cl
		    mov     ch, 0
		    mov     al, df_enemy_col
		    mov     df_generic_col, al

		    ; Check if finished flag is set "1"
		    cmp     df_finished_flg, 1
		    je      end_drwflt_prc

		    ; If not, set it, and go through the loop one
		    ; more time
		    mov     df_finished_flg, 1
		    jmp     df_redbar_loop


		    ; -------------------------
		    ; Return to calling routine
		    ; -------------------------
    end_drwflt_prc: ret

  draw_flt_stat endp
;=========================================================================
  plot_hit_miss proc
    ; This procedure plots hit, miss, or sink graphics on the screen
    ; given the row/column info and whether it was a hit or miss.
    ; It is called for both allied and enemy plotting.
    ; INPUT:  pl_row, pl_column, pl_grid (A or E), bl (action)

		    ; -------------------------------------------------------
		    ; Calculate the literal row, col referenced
		    ; NOTE:  base literal of ally is (2,4) of enemy is (2,45)
		    ; -------------------------------------------------------
		    ; Convert row, column from ASCII values to decimal
		    sub     pl_row, $30
		    sub     pl_column, $30

		    ; Calculate literal rows
		    mov     al, pl_row
		    mov     ah, 0
		    mov     dl, 2
		    mul     dl                        ; multiply row by two
		    mov     pl_row, al                ; return literal back to pl_row

		    ; Calculate literal columns
		    mov     al, pl_column
		    mov     ah, 0
		    mov     dl, 4
		    mul     dl                        ; multiply column by four
		    mov     pl_column, al             ; return literal back to pl_column

		    ; Add different bases depending on whether plotting on
		    ; allied or enemy grid
		    cmp     pl_grid, 'A'
		    jne     pl_add_enemy

		    ; Add base for allied grid
		    add     pl_row, 2
		    add     pl_column, 4
		    mov     sp_color, 00010000B       ; Set black background
		    jmp     pl_chk_action

		    ; Add base for enemy grid
    pl_add_enemy:   add     pl_row, 2
		    add     pl_column, 45
		    mov     sp_color, 01000000B       ; Set red background

		    ; --------------------------------------------------
		    ; Choose character string and color to plot based on
		    ; action (H, M, or S)
		    ; --------------------------------------------------
    pl_chk_action:  mov     al, pl_row
		    mov     sp_row, al
		    mov     al, pl_column
		    mov     sp_column, al

		    ; Is action a miss?
		    cmp     bl, 'M'
		    jne     pl_chk_hit

		    ; Yes, select appropiate display settings
		    mov     sp_message, offset pl_miss_chars
		    mov     sp_size, size pl_miss_chars
		    or      sp_color, 00000111B       ; Save background/Ensure white foreground
		    call    string_print
		    jmp     pl_exit

    pl_chk_hit:     ; No, select appropriate hit/sink settings
		    mov     sp_message, offset pl_hit_chars
		    mov     sp_size, size pl_hit_chars
		    mov     sp_color, 10000100B       ; Blinking red on black
		    call    string_print


		    ; Return to calling routine
    pl_exit:        ret

  plot_hit_miss endp
;=========================================================================

code    ends

;**************************************************************

stack   segment     $0400

;**************************************************************

data    segment


  ; Variables for comm_init procedure
  ci_start_msg      db  'Initializing . . . please wait'
  ci_finish_msg     db  'Initialization is complete'

  ; Variable for the delay procedure
  de_old_second     db

  ; Variables for the draw_flt_stat procedure
  df_friend_col     db  1
  df_enemy_col      db  62
  df_friend_str     db  17
  df_enemy_str      db  17
  df_friend_ships   db  "5"                           ; Necessary because value 5
  df_enemy_ships    db  "5"                           ; is a club character
  df_generic_col    db
  df_generic_str    db
  df_finished_flg   db

  ; Variables for the draw_ship procedure
  ds_begin_row      db
  ds_begin_col      db
  ds_ship_length    db
  ds_ship_direct    db
  ds_ship_chars     db  3 dup ($b0)
  ds_ship_color     db  01111000B

  ; Variables for the initialize procedure
  in_full_line      db  80 dup (" ")
  in_space          db  " "
  in_slash          db  "\\\\\\\"
  in_top_boxln      db  $c9, 68 dup ($cd), $bb
  in_mid_boxln      db  $ba, 68 dup ($20), $ba
  in_bot_boxln      db  $c8, 68 dup ($cd), $bc
  in_title_ln1      db  'G . R . A . D . E . S .'
  in_title_ln2      db  'G - r a p h i c a l'
  in_title_ln3      db  'R - e p r e s e n t a t i o n   o f'
  in_title_ln4      db  'A - t t a c k /'
  in_title_ln5      db  'D - e f e n s e'
  in_title_ln6      db  'E - v a l u a t i o n'
  in_title_ln7      db  'S - y s t e m'
  in_title_ln8      db  '(Developed by Tony Burge)'
  in_title_prompt1  db  'What is the event delay in seconds (0-9)?  '
  in_title_prompt2  db  '            Are we attacking first (Y/N)?  '

  ; Variables for plot_hit_miss procedure
  pl_row            db
  pl_column         db
  pl_grid           db                                ; A=mark on ally's E=mark on enemy's
  pl_hit_chars      db  3 dup ($2a)                   ; An asterisk
  pl_miss_chars     db  3 dup ($09)                   ; A hollow circle

  ; Variables for read_coordinates procedure
  rc_our_row        db
  rc_our_column     db
  rc_attack_msg     db  'Enemy attacked us at ( , )'
  rc_coord_offst    dw  $0016                         ; Equivalent of decimal 22

  ; Variables for read_response procedure
  rr_hit_msg        db  '     *** and it was a HIT!'
  rr_miss_msg       db  '     --- and it was a miss.'
  rr_sink_msg       db  '***  We sank an enemy ship!  ***'
  rr_error_msg      db  'Invalid character received:   '
  rr_error_offst    dw  $001e                         ; Equivalent of decimal 30
  rr_hit_flag       db  'F'                           ; Initially set to False
  rr_sinking_flag   db  'F'
  rr_current_row    db
  rr_current_col    db
  rr_orig_row       db
  rr_orig_col       db
  rr_hit_direction  db                                ; 0=Left, 1=Right, 2=Up, 3=Down

  ; Variables for the char_send_ack routine
  sa_send_error     db  'ERROR:  Unsuccessful transmission'

  ; Variables for send_coords routine
  sc_attack_row     db
  sc_attack_col     db
  sc_attack_msg     db  'We attacked enemy at ( , )'
  sc_coord_offst    dw  $0016                         ; Equivalent of decimal 22

  ; Variable for the scroll_msgmon procedure
  sm_msgtxt_col     db  00100000B       ; Bright white on blue

  ; Variables for the string_print procedure
  sp_column         db
  sp_color          db
  sp_message        dw
  sp_row            db
  sp_size           dw

  ; Variables for send_response procedure
  sr_hit_msg        db  '     --- they hit us'
  sr_miss_msg       db  '     --- they missed us!'
  sr_sink_msg       db  'Oh, no! They sunk one of ours'
  sr_array_loc      dw

  ; Variables & parameters for the screen_setup procedure
  ss_top_grid       db  $da, $c4, $c4, $c4, $c2, $c4, $c4, $c4, $c2, $c4, $c4, $c4
		    db  $c2, $c4, $c4, $c4, $c2, $c4, $c4, $c4, $c2, $c4, $c4, $c4
		    db  $c2, $c4, $c4, $c4, $c2, $c4, $c4, $c4, $bf
  ss_top_grid_size  equ $-ss_top_grid
  ss_mid1_grid      db  $b3, "   ", $b3, "   ", $b3, "   ", $b3, "   "
		    db  $b3, "   ", $b3, "   ", $b3, "   ", $b3, "   ", $b3
  ss_mid1_grid_size equ $-ss_mid1_grid
  ss_mid2_grid      db  $c3, $c4, $c4, $c4, $c5, $c4, $c4, $c4, $c5, $c4, $c4, $c4
		    db  $c5, $c4, $c4, $c4, $c5, $c4, $c4, $c4, $c5, $c4, $c4, $c4
		    db  $c5, $c4, $c4, $c4, $c5, $c4, $c4, $c4, $b4
  ss_mid2_grid_size equ $-ss_mid2_grid
  ss_bot_grid       db  $c0, $c4, $c4, $c4, $c1, $c4, $c4, $c4, $c1, $c4, $c4, $c4
		    db  $c1, $c4, $c4, $c4, $c1, $c4, $c4, $c4, $c1, $c4, $c4, $c4
		    db  $c1, $c4, $c4, $c4, $c1, $c4, $c4, $c4, $d9
  ss_bot_grid_size  equ $-ss_bot_grid
  ss_bot_shadow     db  33 dup ($df)
  ss_side_shadow    db  $db
  ss_top_statbar    db  $d5, 17 dup ($d1), $b8
  ss_mid_statbar    db  $b3, 17 dup ($20), $b3
  ss_bot_statbar    db  $d4, 17 dup ($cf), $be
  ss_top_msgmon     db  $c9, 5 dup ($cd), "< GRADES Message Monitor >", 5 dup ($cd), $bb
  ss_mid_msgmon     db  $ba, 36 dup ($20), $ba
  ss_bot_msgmon     db  $c8, 36 dup ($cd), $bc
  ss_allied_text    db  "      ALLIED FLEET:    SHIPS     "
  ss_enemy_text     db  "      ENEMY FLEET:    SHIPS      "
  ss_text2          db  "Fleet  Strength", 46 dup ($20), "Fleet  Strength"
  ss_row            db
  ss_column         db
  ss_ship_color     db 00010110B                      ; Brown on blue
  ss_frnd_grid_col  db 00010111B                      ; White on blue
  ss_enem_grid_col  db 01000111B                      ; White on red

  ; Global variables used through out the program
  video_page        db
  delay             db
  gv_begin_msg      db  "Battle has begun."
  gv_my_turn        db
  gv_strat_array    dw  "11", "62", "33", "15", "66"  ; Strategy 1 Prime coordinates
		    dw  "00", "44", "22", "77"        ; Strategy 2 coordinates
		    dw  "71", "06", "17", "60", "53"  ; Strategy 3 coordinates
		    dw  "24"
		    dw  "40", "35", "42", "37"        ; Strategy 4 coordinates
		    dw  "73", "13", "64", "04"        ; Strategy 5 coordinates
		    dw  "75", "02", "20", "57"        ; Strategy 6 coordinates
		    dw  "55", "26", "31", "51", "46"  ; Strategy 7 coordinates
		    dw  "01030507101214162123252730"  ; Strategy 8 coordinates.  "Fill-in"
		    dw  "32343641434547505254566163"  ; holes not in prior strategies.
		    dw  "656770727476"
  gv_strat_ptr      dw  $0000                              ; Stores offset into gv_strat_array
  gv_ally_array     dw  "EE", "02", "03", "EE"             ; Coordinates of ship 1
		    dw  "15", "16", "17", "EE"             ; Coordinates of ship 2
		    dw  "61", "62", "63", "64", "EE"       ; Coordinates of ship 3
		    dw  "26", "36", "46", "56", "66", "EE" ; Coordinates of ship 4
		    dw  "30", "40", "50", "EE"             ; Coordinates of ship 5
		    dw  "XX"                               ; End of array marker
							   ; "EE" = end of ship markers
  gv_attackd_array  dw  64 dup ('XX')                 ; track which coordinates we've attacked
  gv_attackd_ptr    dw  $0000
  gv_did_we_win     db

  ; Variables for win_lose_proc procedure
  wl_row            db
  wl_column         db
  wl_won_msg1       db  "  * * *  G R E A T   J O B  * * *"
  wl_won_msg2       db  "          Y o u   W o n !"
  wl_lost_msg1      db  "  - - -  I ' M   S O R R Y  - - -"
  wl_lost_msg2      db  "         Y o u   L o s t ."
  wl_line_msg       db  "////////////////////////////////////"
  wl_hitkey_msg     db  "       Hit any key to exit."
  wl_byebye_msg     db  "Thank you for playing G.R.A.D.E.S.  Have a nice day!"


data    ends

;**************************************************************

	; end of module GRADES.ASM mark for compiler
	end
