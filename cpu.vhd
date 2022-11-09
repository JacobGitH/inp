-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <xkopec58 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  signal pc_register : std_logic_vector(11 downto 0); --PC
  signal pc_increment : std_logic;
  signal pc_decrement : std_logic;
  signal pc_load : std_logic;

  signal ptr_register : std_logic_vector(11 downto 0); --ptr
  signal ptr_increment : std_logic;
  signal ptr_decrement : std_logic;
  
  signal cnt_register : std_logic_vector(11 downto 0); --cnt
  signal cnt_decrement : std_logic;
  signal cnt_increment : std_logic;

  --MX 1
  signal mx1_output : std_logic_vector(12 downto 0);
  signal mx1_select : std_logic_vector(1 downto 0);

  --MX 2
  signal mx2_output : std_logic_vector(7 downto 0);
  signal mx2_select : std_logic_vector(1 downto 0);
  
  --FSM
  type FSM_state is (
    state_idle,
    state_fetch,
    state_fetch1, 
    state_decode,
    state_data_increment0,
    state_data_increment1,
    state_data_increment2,
    state_data_increment3,
    state_data_decrement1,
    state_data_decrement2,
    state_data_decrement3,

    state_ptr_increment,
    state_ptr_decrement,

    state_while_start1,
    state_while_start2,
    state_while_do1,
    state_while_do2,

    state_while_end1,
    state_while_end2,
    state_while_end_do1,
    state_while_end_do2,

    state_do_while_start1,
    state_do_while_start2,
    state_do_while_do1,
    state_do_while_do2,

    state_do_while_end1,
    state_do_while_end2,
    state_do_while_end_do1,
    state_do_while_end_do2,
    state_do_add_inc,

    do1,
    do2,
    do3,


    state_print,
    state_print1,
    state_print2,


    state_read,
    state_read1,
    state_read2,
    state_return,
    state_add_inc
  );

  signal fsm_f_state : FSM_state := state_idle;
  signal fsm_n_state : FSM_state;

begin

-- PC counter
-----------------------------------------------------------------------------
  pc_counter: process (CLK, RESET, pc_decrement, pc_increment, pc_load) is 
  begin
    if RESET = '1' then
      pc_register <= (others => '0');
    elsif (CLK'event) and (CLK = '1') then
      if (pc_load = '1') then
        pc_register <= (others => '0'); 
      elsif (pc_increment = '1') then
        pc_register <= pc_register + 1; 
      elsif (pc_decrement = '1') then
        pc_register <= pc_register - 1; 
      end if;
    end if;
  end process;

-----------------------------------------------------------------------------


-- PTR counter
-----------------------------------------------------------------------------
  ptr_counter: process (CLK, RESET, ptr_decrement, ptr_increment) is 
  begin
    if RESET = '1' then
      ptr_register <= (others => '0');
    elsif (CLK'event) and (CLK = '1') then
      if (ptr_increment = '1') then
        ptr_register <= ptr_register + 1; 
      elsif (ptr_decrement = '1') then
        ptr_register <= ptr_register - 1; 
      end if;
    end if;
  end process;

-----------------------------------------------------------------------------

-- counter

--MX1
-----------------------------------------------------------------------------
mux_mx1: process(CLK, RESET, mx1_select) is
begin
  if RESET = '1' then
    mx1_output <= (others => '0');
  elsif (CLK'event) and (CLK = '1') then
    case mx1_select is 
      when "00" => mx1_output <= (others => '0');
      when "01"  => mx1_output <=   "0000000000000" + pc_register;
      when "10" => mx1_output <=   "1000000000000" + ptr_register;
      when others => null;
    end case;
  end if;
end process;

DATA_ADDR <= mx1_output;


-----------------------------------------------------------------------------


--MX2
-----------------------------------------------------------------------------
mux_mx2: process(CLK, RESET, mx2_select) is
begin
  if RESET = '1' then
    mx2_output <= (others => '0');
  elsif (CLK'event) and (CLK = '1') then
    case mx2_select is 
      when "00" => mx2_output <= IN_DATA;
      when "01" => mx2_output <= DATA_RDATA + 1;
      when "10" => mx2_output <= DATA_RDATA - 1;
      when "11"=> mx2_output <= DATA_RDATA;
      when others => null;
    end case;
  end if;
end process;

DATA_WDATA <= mx2_output;
OUT_DATA <= DATA_RDATA;
-----------------------------------------------------------------------------

--FSM_pstate
-----------------------------------------------------------------------------
fsm_pstate_logic: process (CLK, RESET, EN) is
begin
  if RESET = '1' then
    fsm_f_state <= state_idle;
  elsif (CLK'event) and (CLK = '1') then
    if EN = '1' then
      fsm_f_state <= fsm_n_state;
    end if;
  end if;
end process;
-----------------------------------------------------------------------------


fsm_nstate_logic: process(fsm_f_state, OUT_BUSY, IN_VLD, DATA_RDATA) is
begin
  pc_increment  <= '0';
  pc_decrement  <= '0';
  pc_load       <= '0';
  ptr_increment <= '0';
  ptr_decrement <= '0';
  DATA_EN       <= '0';
  DATA_RDWR     <= '0';
  IN_REQ        <= '0';
  OUT_WE        <= '0';
  mx2_select    <= "00";
  mx1_select    <= "01";

  case fsm_f_state is
    when state_idle => fsm_n_state <= state_fetch;
    when state_fetch => DATA_EN <= '1';
                        mx1_select  <= "01";
                        fsm_n_state <= state_fetch1;
    when state_fetch1 =>
        fsm_n_state <= state_decode;
    when state_decode => 
      case DATA_RDATA is 
      
        when X"3E" => fsm_n_state <= state_ptr_increment;
        when X"3C" => fsm_n_state <= state_ptr_decrement;

        when X"2B" => 
          mx1_select <= "10";
          fsm_n_state <= state_data_increment1;
        when X"2D" => 
          mx1_select <= "10";
          fsm_n_state <= state_data_decrement1;

        when X"5B" => 
          mx1_select <= "10";
          mx2_select <= "11";
          fsm_n_state <= state_while_start1;
        when X"5D" => 
          mx1_select <= "10";
          mx2_select <= "11";
          fsm_n_state <= state_while_end1;

        when X"28" => 
        mx1_select <= "10";
        mx2_select <= "11";
        fsm_n_state <= do1;
        when X"29" => 
        mx1_select <= "10";
        mx2_select <= "11";
        fsm_n_state <= state_do_while_end1;

        when X"2E" => 
          mx2_select <= "11";
          mx1_select <= "10";
          fsm_n_state <= state_print;
        when X"2C" =>
          mx1_select <= "10";
          fsm_n_state <= state_read;
        when X"00" => null;

        when others => 
          pc_increment <= '1';
          fsm_n_state <= state_fetch;
      end case;
    --Ptr Increment------------------------------  
    when  state_ptr_increment =>
            ptr_increment <= '1';
            pc_increment <= '1'; 
            fsm_n_state <= state_idle;
    when  state_ptr_decrement =>
            ptr_decrement <= '1';
            pc_increment <= '1'; 
            fsm_n_state <= state_idle;
    
 --Data increment--------------------------------------   
    when  state_data_increment1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            fsm_n_state <= state_data_increment2;
    when state_data_increment2 => 
            mx1_select <= "10";
            mx2_select <= "01";
            fsm_n_state <= state_data_increment3;
    when state_data_increment3 => 
            mx1_select <= "10";
            mx2_select <= "01";
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            pc_increment <= '1';
            fsm_n_state <= state_idle;
  ------------------------------------------------------    

--Data Decrement--------------------------------------
    when  state_data_decrement1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            fsm_n_state <= state_data_decrement2;
    when state_data_decrement2 => 
            mx1_select <= "10";
            mx2_select <= "10";
            fsm_n_state <= state_data_decrement3;
    when state_data_decrement3 => 
            mx1_select <= "10";
            mx2_select <= "10";
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            pc_increment <= '1';
            fsm_n_state <= state_idle;
  ------While LOOP------------------------------------------------     
    when state_while_start1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            pc_increment <= '1';
            mx1_select <= "10";
            fsm_n_state <= state_while_start2;
    when state_while_start2 => 
            if DATA_RDATA = "00000000" then
              fsm_n_state <= state_while_do1;
              mx1_select <= "01";
            else
              fsm_n_state <= state_fetch;
            end if;

    when state_while_do1 =>
            if DATA_RDATA = X"5D" then
              fsm_n_state <= state_fetch;
            else
              fsm_n_state <= state_while_do2;
              pc_increment <= '1';
              
            end if;
    when state_while_do2 =>        
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            fsm_n_state <= state_while_do1;
    
    ----END WHILE LOOP-------------------------
    when state_while_end1 => 
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx1_select <= "10";
            fsm_n_state <= state_while_end2;
    when state_while_end2 =>
            if DATA_RDATA /= "00000000" then
              fsm_n_state <= state_while_end_do1;
              mx1_select <= "01";
            else
              pc_increment <= '1';
              fsm_n_state <= state_fetch;
            end if;
    when state_while_end_do1 =>
              if DATA_RDATA = X"5B" then
              pc_increment <= '1';
              fsm_n_state <= state_add_inc;
            else
              pc_decrement <= '1';
              fsm_n_state <= state_while_end1;
            end if;
    when state_while_end_do2 =>
          mx1_select <= "01";
          fsm_n_state <= state_while_end_do1;
    when state_add_inc =>  --I really hate my life right now
            fsm_n_state <= state_fetch;
    ------------------------------------------------------------
    --DO WHILE START--------------------------------------------

    when do1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            pc_increment <= '1';
            mx1_select <= "10";
            fsm_n_state <= do2;
    when do2 =>
              fsm_n_state <= state_do_while_do1;
              mx1_select <= "01";
              fsm_n_state <= state_fetch;
    when state_do_while_start1 =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            pc_increment <= '1';
            mx1_select <= "10";
            fsm_n_state <= state_do_while_start2;
    when state_do_while_start2 => 
            if DATA_RDATA = "00000000" then
              fsm_n_state <= state_do_while_do1;
              mx1_select <= "01";
              --DATA_EN <= '1';
              --DATA_RDWR <= '0';
            else
              fsm_n_state <= state_fetch;
            end if;

    when state_do_while_do1 =>
            if DATA_RDATA = X"29" then
              fsm_n_state <= do3;
              pc_decrement <= '1';
            else
              fsm_n_state <= state_do_while_do2;
              pc_increment <= '1';
              
            end if;
    when state_do_while_do2 =>        
           -- mx1_select <= "01";
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              fsm_n_state <= state_do_while_do1;
    when do3 =>
    fsm_n_state <= state_fetch;




    ---DO WHILE END--------------------------------------------------------


    when state_do_while_end1 => 
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx1_select <= "10";
            fsm_n_state <= state_do_while_end2;
    when state_do_while_end2 =>
            if DATA_RDATA /= "00000000" then
              fsm_n_state <= state_do_while_end_do1;
              mx1_select <= "01";
              --DATA_EN <= '1';
              --DATA_RDWR <= '0';
              --pc_decrement <= '1';
            else
              pc_increment <= '1';
              fsm_n_state <= state_fetch;
            end if;
    when state_do_while_end_do1 =>
              if DATA_RDATA = X"28" then
              pc_increment <= '1';
              fsm_n_state <= state_do_add_inc;
            else
              pc_decrement <= '1';
              fsm_n_state <= state_do_while_end1;
            end if;
    when state_do_while_end_do2 =>
          --pc_decrement <= '1';
          --DATA_EN <= '1';
          --DATA_RDWR <= '0';
          mx1_select <= "01";
          fsm_n_state <= state_do_while_end_do1;
    when state_do_add_inc =>  
            --pc_increment <= '1';
            fsm_n_state <= state_fetch;
    ------READ--------------------------------------------------        
    when state_read =>
      mx2_select <= "00";
      mx1_select <= "10";
      
      IN_REQ <= '1';
      fsm_n_state <= state_read1;
    when state_read1 =>
    mx1_select <= "10";
      if IN_VLD /= '1' then
        IN_REQ <= '1';
        mx2_select <= "00";
        fsm_n_state <= state_read1;
      else 
        pc_increment <= '1';
        fsm_n_state <= state_read2;
      end if;

    when state_read2 => 
        mx1_select <= "01";
        DATA_EN <= '1';
        DATA_RDWR <= '1';
    fsm_n_state <= state_fetch;

    ----PRINT--------------------------------------------------------
    when state_print =>
    DATA_EN <= '1';
    DATA_RDWR <= '0';
    mx1_select <= "10";
    fsm_n_state <= state_print1;
    mx2_select <= "11";

    when state_print1 =>
    mx2_select <= "11";
    mx1_select <= "10";
    if OUT_BUSY = '1' then
      DATA_EN <= '1';
      DATA_RDWR <= '0';
      fsm_n_state <= state_print1;
    else 
      OUT_WE <= '1';
      pc_increment <= '1'; 
      fsm_n_state <= state_print2;
    end if;
     
    when state_print2 =>
      mx2_select <= "11";
      mx1_select <= "01";   
      DATA_EN <= '1';
      DATA_RDWR <= '0';
      fsm_n_state <= state_fetch;

    when state_return =>
      fsm_n_state <= state_return;
      
    when others => null;

    end case;      
end process;




end behavioral;

