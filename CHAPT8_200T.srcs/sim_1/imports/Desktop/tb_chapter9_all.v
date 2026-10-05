`timescale 1ns/1fs

// Teaching-manual Chapter 9 -> chapter8_game_interface_200t.xpr.
// Simulation top: tb_chapter9_all. Run 35 ms. Expected: CH9 PASS.
// Actual project modules under test: ui_fsm_chapter8, game_system_5slot,
// game_stub, lcd_timing_1024x600_frame, frame_snapshot_bus, tick_generator.
// This is an interface-level simulation: events enter at the UI/game ports.
// It does not simulate the PS/2/I2C drivers, MMCM, or physical LCD/board.
// The LCD timing constants and 51.2 MHz clock are not accelerated.
// Fast slot checks use explicit test_game_tick/test_tick_1s inputs;
// the separate real tick generator retains its production parameters.
// No design-source edits, force statements, $finish, or $stop are required.
//
// Figure 9-1: 8..94 us. Add ui_state, menu_sel, enable, event_ok,
//             event_back, slot_exit, exit_request, touch_button_valid.
// Figure 9-2: 0..35 ms. Add rst_n, frame_start, frame_ordinal,
//             live_bus, frame_bus, ui_state, ui_state_frame,
//             menu_sel, menu_sel_frame. Packed buses: hexadecimal.
// Packed state layout, identical to the project top:
// [25:23] ui_state, [22:20] menu_sel, [19:4] game_score, [3:0] game_state.

module tb_chapter9_all;
    reg pix_clk = 1'b0;
    always #9.765625 pix_clk = ~pix_clk; // exactly 51.2 MHz
    reg rst_n = 1'b0;

    reg event_up = 1'b0;
    reg event_down = 1'b0;
    reg event_left = 1'b0;
    reg event_right = 1'b0;
    reg event_ok = 1'b0;
    reg event_back = 1'b0;
    reg event_pause = 1'b0;
    reg touch_button_valid = 1'b0;
    reg [2:0] touch_button_index = 3'd0;
    reg test_exit_request = 1'b0;
    reg test_game_tick = 1'b0;
    reg test_tick_1s = 1'b0;

    wire [2:0] ui_state;
    wire [2:0] menu_sel;
    wire [2:0] ui_state_frame;
    wire [2:0] menu_sel_frame;
    wire [15:0] game_score_frame;
    wire [3:0] game_state_frame;
    wire exit_request;
    wire [4:0] enable = u_games.enable;
    wire [4:0] slot_exit = u_games.slot_exit;
    wire game_pixel_on;
    wire [23:0] game_pixel_rgb;
    wire [15:0] game_score;
    wire [3:0] game_state;

    ui_fsm_chapter8 u_ui (
        .clk(pix_clk), .rst_n(rst_n),
        .event_up(event_up), .event_down(event_down),
        .event_ok(event_ok), .event_back(event_back),
        .touch_button_valid(touch_button_valid),
        .touch_button_index(touch_button_index),
        .game_exit_request(exit_request | test_exit_request),
        .ui_state(ui_state), .menu_sel(menu_sel)
    );

    wire [10:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;
    wire hsync, vsync;
    wire frame_start;
    wire [10:0] h_count = u_timing.h_count;
    wire [9:0] v_count = u_timing.v_count;

    lcd_timing_1024x600_frame u_timing (
        .pix_clk(pix_clk), .rst_n(rst_n),
        .x(pixel_x), .y(pixel_y), .active_video(active_video),
        .hsync(hsync), .vsync(vsync), .frame_start(frame_start)
    );

    wire game_tick_real;
    wire tick_1s_real;
    tick_generator #(.CLK_HZ(51_200_000), .GAME_TICK_HZ(60)) u_ticks (
        .clk(pix_clk), .rst_n(rst_n),
        .game_tick(game_tick_real), .tick_1s(tick_1s_real)
    );
    wire game_tick = test_game_tick | game_tick_real;
    wire tick_1s = test_tick_1s | tick_1s_real;

    game_system_5slot u_games (
        .clk(pix_clk), .rst_n(rst_n),
        .ui_state_control(ui_state), .ui_state_frame(ui_state_frame),
        .event_up(event_up), .event_down(event_down),
        .event_left(event_left), .event_right(event_right),
        .event_ok(event_ok), .event_back(event_back),
        .event_pause(event_pause),
        .game_tick(game_tick), .tick_1s(tick_1s),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_on(game_pixel_on), .pixel_rgb(game_pixel_rgb),
        .score(game_score), .game_state(game_state),
        .exit_request(exit_request)
    );

    wire [25:0] live_bus = {ui_state, menu_sel, game_score, game_state};
    wire [25:0] frame_bus;
    frame_snapshot_bus #(.WIDTH(26)) u_snapshot (
        .clk(pix_clk), .rst_n(rst_n), .frame_start(frame_start),
        .live_bus(live_bus), .frame_bus(frame_bus)
    );
    assign {ui_state_frame, menu_sel_frame,
            game_score_frame, game_state_frame} = frame_bus;

    // Direct aliases of actual live registers; used to check inactive slots.
    wire [54:0] players_x = {
        u_games.u_game5.player_x, u_games.u_game4.player_x,
        u_games.u_game3.player_x, u_games.u_game2.player_x,
        u_games.u_game1.player_x};
    wire [49:0] players_y = {
        u_games.u_game5.player_y, u_games.u_game4.player_y,
        u_games.u_game3.player_y, u_games.u_game2.player_y,
        u_games.u_game1.player_y};
    wire [79:0] scores_live = {
        u_games.u_game5.score_live, u_games.u_game4.score_live,
        u_games.u_game3.score_live, u_games.u_game2.score_live,
        u_games.u_game1.score_live};
    wire [19:0] states_live = {
        u_games.u_game5.game_state_live, u_games.u_game4.game_state_live,
        u_games.u_game3.game_state_live, u_games.u_game2.game_state_live,
        u_games.u_game1.game_state_live};

    integer case_id = 0;
    integer errors = 0;
    integer slot_tests = 0;
    integer frame_ordinal = 0;
    integer real_tick_count = 0;
    integer pixel_cycles = 0;
    integer last_frame_cycle = 0;
    integer last_tick_cycle = 0;
    reg checks_done = 1'b0;
    reg checks_pass = 1'b0;
    reg [25:0] expected_frame = 26'd0;
    reg [4:0] sampled_enable = 5'd0;
    reg [54:0] old_x = 55'd0;
    reg [49:0] old_y = 50'd0;
    reg [79:0] old_scores = 80'd0;
    reg [19:0] old_states = 20'd0;
    reg old_frame_start = 1'b0;
    reg old_real_tick = 1'b0;
    integer monitor_i;

    task check;
        input condition;
        input [511:0] message;
        begin
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("CH9 FAIL at %0.3f us: %0s", $realtime/1000.0, message);
            end
        end
    endtask

    // Check the full 26-bit snapshot on every active clock. The sampled
    // expected value is taken before the DUT's nonblocking assignments.
    always @(posedge pix_clk) begin
        sampled_enable = enable;
        old_x = players_x;
        old_y = players_y;
        old_scores = scores_live;
        old_states = states_live;
        if (!rst_n) begin
            expected_frame = 26'd0;
            frame_ordinal = 0;
            real_tick_count = 0;
            pixel_cycles = 0;
            last_frame_cycle = 0;
            last_tick_cycle = 0;
            old_frame_start = 1'b0;
            old_real_tick = 1'b0;
        end else begin
            pixel_cycles = pixel_cycles + 1;
            if (frame_start) begin
                check(!old_frame_start, "frame_start wider than one pixel clock");
                check(h_count == 160 && v_count == 23,
                      "frame_start did not come from the real LCD counters");
                if (frame_ordinal != 0)
                    check(pixel_cycles - last_frame_cycle == 853440,
                          "LCD frame period is not 1344 x 635 clocks");
                last_frame_cycle = pixel_cycles;
                frame_ordinal = frame_ordinal + 1;
                expected_frame = live_bus;
                $display("CH9 FRAME %0d at %0.6f us: live=%07h",
                         frame_ordinal, $realtime/1000.0, live_bus);
            end
            if (game_tick_real) begin
                check(!old_real_tick, "real game_tick wider than one clock");
                if (real_tick_count != 0)
                    check(pixel_cycles - last_tick_cycle == 853333,
                          "real game_tick period is not CLK_HZ / 60");
                last_tick_cycle = pixel_cycles;
                real_tick_count = real_tick_count + 1;
            end
            check(!tick_1s_real, "one-second tick occurred before one second");
            old_frame_start = frame_start;
            old_real_tick = game_tick_real;
        end
        #0.001;
        check(frame_bus === expected_frame, "snapshot reset/capture/hold mismatch");
        if (rst_n) begin
            check((enable & (enable - 5'd1)) == 5'd0,
                  "more than one game slot enabled");
            for (monitor_i = 0; monitor_i < 5; monitor_i = monitor_i + 1) begin
                if (!sampled_enable[monitor_i]) begin
                    check(players_x[monitor_i*11 +: 11] === old_x[monitor_i*11 +: 11]
                       && players_y[monitor_i*10 +: 10] === old_y[monitor_i*10 +: 10]
                       && scores_live[monitor_i*16 +: 16] === old_scores[monitor_i*16 +: 16]
                       && states_live[monitor_i*4 +: 4] === old_states[monitor_i*4 +: 4],
                          "inactive slot changed live position/score/state");
                end
            end
            // Output selection uses the captured page, independently of
            // current control-page enable. This mirrors the project top.
            case (ui_state_frame)
                3'd2: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                         === {u_games.slot_on[0],u_games.slot_rgb0,u_games.slot_score0,u_games.slot_state0}, "slot 1 output mux");
                3'd3: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                         === {u_games.slot_on[1],u_games.slot_rgb1,u_games.slot_score1,u_games.slot_state1}, "slot 2 output mux");
                3'd4: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                         === {u_games.slot_on[2],u_games.slot_rgb2,u_games.slot_score2,u_games.slot_state2}, "slot 3 output mux");
                3'd5: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                         === {u_games.slot_on[3],u_games.slot_rgb3,u_games.slot_score3,u_games.slot_state3}, "slot 4 output mux");
                3'd6: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                         === {u_games.slot_on[4],u_games.slot_rgb4,u_games.slot_score4,u_games.slot_state4}, "slot 5 output mux");
                default: check({game_pixel_on,game_pixel_rgb,game_score,game_state}
                            === 45'd0, "non-game frame page did not blank game output");
            endcase
        end
    end

    task at_us;
        input integer target_us;
        real delay_ns;
        begin
            delay_ns = target_us * 1000.0 - $realtime;
            if (delay_ns > 0) #(delay_ns);
            @(negedge pix_clk);
        end
    endtask

    task select_button;
        input [2:0] index;
        begin
            @(negedge pix_clk);
            touch_button_index = index;
            touch_button_valid = 1'b1;
            @(negedge pix_clk);
            touch_button_valid = 1'b0;
            #0.001;
        end
    endtask

    // Mask bits: 0 up, 1 down, 2 left, 3 right, 4 OK, 5 Back,
    // 6 pause, 7 explicit unit-test game tick, 8 explicit unit-test 1s tick.
    task pulse;
        input [8:0] mask;
        begin
            @(negedge pix_clk);
            {test_tick_1s,test_game_tick,event_pause,event_back,event_ok,
             event_right,event_left,event_down,event_up} = mask;
            #0.001;
            if (mask[5]) begin
                if (ui_state >= 2 && ui_state <= 6) begin
                    check(exit_request && slot_exit == enable,
                          "Back did not create the selected slot exit request");
                end else check(!exit_request && slot_exit == 0,
                               "non-game page produced a game exit request");
            end
            @(negedge pix_clk);
            {test_tick_1s,test_game_tick,event_pause,event_back,event_ok,
             event_right,event_left,event_down,event_up} = 9'd0;
            #0.001;
        end
    endtask

    // During the first 94 us all five slots are checked while the genuine
    // LCD scan is still in vertical blanking (pixel_x=pixel_y=0).
    integer s;
    integer base_us;
    reg [10:0] saved_x;
    reg [15:0] saved_score;
    initial begin
        at_us(1);
        rst_n = 1'b1;
        #0.001;
        check(ui_state == 0 && enable == 0 && frame_bus == 0,
              "reset initialization failed");

        for (s = 0; s < 5; s = s + 1) begin
            case_id = s + 1;
            base_us = 10 + s * 15;
            at_us(base_us);
            select_button(s + 1);
            check(ui_state == s + 2 && menu_sel == s + 1,
                  "button did not select the corresponding game page");
            check(enable == (5'b00001 << s), "slot enable bit order is wrong");

            at_us(base_us + 2);
            pulse(9'h010); // start selected game
            check(states_live[s*4 +: 4] == 1, "selected game did not start");
            saved_x = players_x[s*11 +: 11];
            at_us(base_us + 3);
            pulse(9'h008); // buffer right event
            check(players_x[s*11 +: 11] == saved_x,
                  "movement occurred before a game tick");
            pulse(9'h080); // consume buffered direction
            check(players_x[s*11 +: 11] == saved_x + 8,
                  "buffered right event did not move exactly 8 pixels");
            saved_x = players_x[s*11 +: 11];
            pulse(9'h080);
            check(players_x[s*11 +: 11] == saved_x,
                  "direction event was consumed more than once");

            at_us(base_us + 4);
            pulse(9'h100);
            check(scores_live[s*16 +: 16] == 1, "selected score did not increment");
            saved_score = scores_live[s*16 +: 16];
            at_us(base_us + 5);
            pulse(9'h040); // pause
            check(states_live[s*4 +: 4] == 2, "pause state missing");
            at_us(base_us + 6);
            pulse(9'h008);
            pulse(9'h180); // game tick + 1s tick while paused
            check(players_x[s*11 +: 11] == saved_x
               && scores_live[s*16 +: 16] == saved_score,
                  "paused slot changed position or score");

            at_us(base_us + 8);
            pulse(9'h040); // resume
            check(states_live[s*4 +: 4] == 1, "resume state missing");
            at_us(base_us + 10);
            pulse(9'h020); // real game_stub exit + UI return
            check(ui_state == 0 && enable == 0 && !exit_request,
                  "game exit did not return to HOME with slots disabled");
            slot_tests = slot_tests + 1;
        end

        at_us(85); case_id = 6;
        select_button(0); // UI state 1, input-information page
        check(ui_state == 1 && enable == 0, "state 1 enabled a game slot");
        at_us(87); pulse(9'h020);
        at_us(90); case_id = 7;
        select_button(6); // UI state 7, system-information page
        check(ui_state == 7 && enable == 0, "state 7 enabled a game slot");
        at_us(92); pulse(9'h020);
        check(ui_state == 0 && enable == 0, "non-game page Back failed");

        // Check that an application's independent request also returns HOME.
        at_us(95); case_id = 8;
        select_button(1);
        @(negedge pix_clk); test_exit_request = 1'b1;
        @(negedge pix_clk); test_exit_request = 1'b0;
        #0.001;
        check(ui_state == 0 && enable == 0, "independent game exit request failed");

        // Snapshot demonstration, using the unchanged physical scan period.
        at_us(100); case_id = 9;
        select_button(1); // live UI 2; first capture at about 607.9 us
        check(frame_bus == 0, "frame updated before the first frame_start");
        at_us(800);
        check(frame_ordinal == 1 && ui_state_frame == 2 && menu_sel_frame == 1,
              "first real LCD frame did not capture the live page");
        at_us(1000); case_id = 10;
        pulse(9'h020);
        select_button(2); // live UI 3; frame UI remains 2
        check(ui_state == 3 && ui_state_frame == 2,
              "display page failed to hold within the first frame");
        at_us(17500);
        check(frame_ordinal == 2 && ui_state_frame == 3 && menu_sel_frame == 2,
              "second real LCD frame did not capture the new page");
        at_us(18000); case_id = 11;
        pulse(9'h020);
        select_button(3); // live UI 4; frame UI remains 3
        check(ui_state == 4 && ui_state_frame == 3,
              "display page failed to hold within the second frame");
        at_us(34000);
        check(frame_ordinal == 3 && ui_state_frame == 4 && menu_sel_frame == 3,
              "third real LCD frame did not capture the new page");
        at_us(34500);
        check(slot_tests == 5, "not all five slots were checked");
        check(real_tick_count == 2, "wrong number of real 60 Hz game ticks");
        checks_done = 1'b1;
        checks_pass = (errors == 0);
        if (checks_pass)
            $display("CH9 PASS: slots=%0d frames=%0d real_ticks=%0d errors=%0d",
                     slot_tests, frame_ordinal, real_tick_count, errors);
        else $display("CH9 FAIL: errors=%0d", errors);
        // Leave the waveform window available for screenshots.
    end
endmodule
