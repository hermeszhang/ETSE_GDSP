----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    19:09:29 02/18/2015 
-- Design Name: 
-- Module Name:    MEMARRAY - Behavioral 
-- Project Name: 
-- Target Devices: 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity MEMARRAY_V2 is
generic(
		COLUMN_TOTAL: integer:=3;
		OPCODE_WIDTH: integer :=3;
      ADDR_WIDTH: integer:=10;
      DATA_WIDTH:integer:=18;
		DATA_WIDE_WIDTH: integer:=48
   );
    Port ( CLK : in  STD_LOGIC;
           ADDRA : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
           ADDRB : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
           WE : in  STD_LOGIC;
           OE : in  STD_LOGIC;
			  SSEN: in STD_LOGIC;			-- scratchpad shift enable
			  ASHFT: in STD_LOGIC;			-- scratchpad shift enable
           OPCODE : in  STD_LOGIC_VECTOR (OPCODE_WIDTH-1 downto 0);
           DOUT : out  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
			  DIN  : in  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
           CSEL : in  STD_LOGIC_VECTOR (COLUMN_TOTAL-1 downto 0));
end MEMARRAY_V2;

architecture Behavioral of MEMARRAY_V2 is
-------------------------------------------COMPONENTS-----------------------
component SCRATCHPAD_REG
generic ( DATA_WIDTH: integer:=18);
    Port ( CLK : in  STD_LOGIC;
           DSRC : in  STD_LOGIC;
           DIN : in  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
           CIN : in  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
           DOUT : out  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0));
end component;
----------------------------------------------------------------------------
COMPONENT DSP_INPUT_C
    PORT(
         clk : IN  std_logic;
         sel : IN  std_logic_vector(2 downto 0);
         a : IN  std_logic_vector(17 downto 0);
         b : IN  std_logic_vector(17 downto 0);
         c : IN  std_logic_vector(47 downto 0);
         p : OUT  std_logic_vector(47 downto 0)
        );
END COMPONENT;
--------------------------------------------------------------------------
COMPONENT BRAM_WRAPPER_V2
generic(
		COLUMN_NUMBER: integer:=0;
		NUM_COLUMNS: integer:=1;
      ADDR_WIDTH: integer:=10;
      DATA_WIDTH:integer:=18
   );
    PORT(
         CLK : IN  std_logic;
         ADDRA : IN  std_logic_vector(9 downto 0);
         DINA : IN  std_logic_vector(17 downto 0);
         ADDRB : IN  std_logic_vector(9 downto 0);
         DOUTB : OUT  std_logic_vector(17 downto 0);
         SHFT : IN  std_logic;
         WEA : IN  std_logic;
         OEB : IN  std_logic
        );
END COMPONENT;
---------------------------------------------------------------------------
type i_DATA_t is array (0 to COLUMN_TOTAL-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
signal i_MEM2ALU:i_DATA_t;				---- mem-to-alu signal
signal i_ALU2SPD:i_DATA_t;				---- alu to scratchpad signal
signal i_SPDOUT:i_DATA_t;				---- scratchpad to mem and scratchpad to scratchpad(n+1) signal
type i_DATA_wide is array (0 to COLUMN_TOTAL-1) of std_logic_vector(DATA_WIDE_WIDTH-1 downto 0);
signal i_ALU2ALU: i_DATA_wide;		---- alu-to-alu signal

constant DIN_DELAY: integer:=2;
constant DELAY_DEPTH: integer:=7+DIN_DELAY;

type pipelined_OPCODE_t is array (0 to DIN_DELAY-1) of  std_logic_vector(OPCODE_WIDTH-1 downto 0);
signal p_OPCODE: pipelined_OPCODE_t;
signal i_OPCODE: std_logic_vector(OPCODE_WIDTH-1 downto 0);


type pipelined_DIN_t is array (0 to DIN_DELAY-1) of  std_logic_vector(DATA_WIDTH-1 downto 0);
signal p_DIN: pipelined_DIN_t;

signal i_DIN: std_logic_vector(DATA_WIDTH-1 downto 0);

type pipelined_B_t is array (0 to DELAY_DEPTH-1) of  std_logic_vector(0 to COLUMN_TOTAL-1);
signal p_WEB,p_OEB: pipelined_B_t;

signal i_WEB: std_logic_vector(0 to COLUMN_TOTAL-1); 

type pipelined_ADDR_t is array (0 to DELAY_DEPTH-1) of std_logic_vector(ADDR_WIDTH-1 downto 0);
signal p_ADDR: pipelined_ADDR_t;
signal i_ADDR: std_logic_vector(ADDR_WIDTH-1 downto 0);

begin

-----------------------------------------------------------
DELAY_GEN: process(CLK)
begin
if rising_edge(CLK) then
	p_ADDR(0)<=ADDRA;
	for i in 0 to COLUMN_TOTAL-1 loop
		p_WEB(0)(i)<=CSEL(i) and WE;
	end loop;
	for i in 1 to DELAY_DEPTH-1 loop
		p_WEB(i)<=p_WEB(i-1);--The Write enable signal is pipelined for 2 + 7 cycles because the output of the DSP computation will have a total latency of 9 clk cycles. 2 for delayed deta input to DSP (A and B) 1 from scratchpad register and about 6 from DSP block.
		p_ADDR(i)<=p_ADDR(i-1);--The Address for A port of the RAM is delayed for 2 + 7 clk cycles because the DSP takes about 6 clk cyles to finish its computation plus 1 clk delay from scratch pad and plus the data inputs which are delayed for 2 clk cyles.
	end loop;
	i_ADDR<=p_ADDR(DELAY_DEPTH-1);
	i_WEB<=p_WEB(DELAY_DEPTH-1);
	
	p_OPCODE(0)<=OPCODE;
	p_DIN(0)<=DIN;
	for i in 1 to DIN_DELAY-1 loop
		p_DIN(i)<=p_DIN(i-1);-- The DIN signal is delayed for 2 clk cycles in order for it to arrive at the same time with the B signal coming from the BRAM which has a latency of 2 clk cycles
		p_OPCODE(i)<=p_OPCODE(i-1);--The opcode is also delayed for 2 clk cycles because it must be sent at the same time with the A and B input of the DSP.
	end loop;
	i_DIN<=p_DIN(DIN_DELAY-1);
	i_OPCODE<=p_OPCODE(DIN_DELAY-1);
end if;
end process;
--------------------------------------------------------------
BLOCK_A_MEM_GEN:
for i in 0 to COLUMN_TOTAL-1 generate
	 MEMA: BRAM_WRAPPER_V2 
	  generic map(
					COLUMN_NUMBER=>i,
					NUM_COLUMNS=>COLUMN_TOTAL,
					ADDR_WIDTH=>ADDR_WIDTH,
					DATA_WIDTH=>DATA_WIDTH)
	 PORT MAP (
          CLK => CLK,
          ADDRA => i_ADDR,
          DINA => i_SPDOUT(i),
          ADDRB => ADDRB,
          DOUTB => i_MEM2ALU(i),
          SHFT => ASHFT,
          WEA => i_WEB(i),
          OEB => CSEL(i)
        );
end generate;
--------------------------------------------------------------
FIRST_DSP:
 DSP_INPUT_C PORT MAP (
          clk => CLK,
          sel => i_OPCODE,
          a => i_DIN,
          b => i_MEM2ALU(0),
          c => i_ALU2ALU(COLUMN_TOTAL-1),
          p => i_ALU2ALU(0)
        );
--------------------------------------------------------------		  
BLOCK_A_DSP_GEN:
for i in 1 to COLUMN_TOTAL-1 generate
DSP: DSP_INPUT_C PORT MAP (
          clk => CLK,
          sel => i_OPCODE,
          a => i_DIN,
          b => i_MEM2ALU(i),
          c => i_ALU2ALU(i-1),
          p => i_ALU2ALU(i)
        );
end generate;
--------------------------------------------------------------
FIRST_SP: SCRATCHPAD_REG 
	 Port map(  CLK=>CLK,
					DSRC=>SSEN,
					DIN=>i_ALU2ALU(0)(DATA_WIDTH-1 downto 0),
					CIN=>i_SPDOUT(COLUMN_TOTAL-1),
					DOUT=>i_SPDOUT(0));
----------------------------------------s----------------------			
SCRATCHPAD_GEN:
for i in 1 to COLUMN_TOTAL-1 generate
SP: SCRATCHPAD_REG 
	 Port map(  CLK=>CLK,
					DSRC=>SSEN,
					DIN=>i_ALU2ALU(i)(DATA_WIDTH-1 downto 0),
					CIN=>i_SPDOUT(i-1),
					DOUT=>i_SPDOUT(i));
end generate;
DOUT<=i_ALU2ALU(COLUMN_TOTAL-1)(DATA_WIDTH-1 downto 0);	
end Behavioral;
