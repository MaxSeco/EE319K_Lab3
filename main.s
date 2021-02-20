;****************** main.s ***************
; Program written by: Valvano, solution
; Date Created: 2/4/2017
; Last Modified: 1/17/2021
; Brief description of the program
;   The LED toggles at 2 Hz and a varying duty-cycle
; Hardware connections (External: One button and one LED)
;  PE1 is Button input  (1 means pressed, 0 means not pressed)
;  PE2 is LED output (1 activates external LED on protoboard)
;  PF4 is builtin button SW1 on Launchpad (Internal) 
;        Negative Logic (0 means pressed, 1 means not pressed)
; Overall functionality of this system is to operate like this
;   1) Make PE2 an output and make PE1 and PF4 inputs.
;   2) The system starts with the the LED toggling at 2Hz,
;      which is 2 times per second with a duty-cycle of 30%.
;      Therefore, the LED is ON for 150ms and off for 350 ms.
;   3) When the button (PE1) is pressed-and-released increase
;      the duty cycle by 20% (modulo 100%). Therefore for each
;      press-and-release the duty cycle changes from 30% to 70% to 70%
;      to 90% to 10% to 30% so on
;   4) Implement a "breathing LED" when SW1 (PF4) on the Launchpad is pressed:
;      a) Be creative and play around with what "breathing" means.
;         An example of "breathing" is most computers power LED in sleep mode
;         (e.g., https://www.youtube.com/watch?v=ZT6siXyIjvQ).
;      b) When (PF4) is released while in breathing mode, resume blinking at 2Hz.
;         The duty cycle can either match the most recent duty-
;         cycle or reset to 30%.
;      TIP: debugging the breathing LED algorithm using the real board.
; PortE device registers
GPIO_PORTE_DATA_R  EQU 0x400243FC
GPIO_PORTE_DIR_R   EQU 0x40024400
GPIO_PORTE_AFSEL_R EQU 0x40024420
GPIO_PORTE_DEN_R   EQU 0x4002451C
; PortF device registers
GPIO_PORTF_DATA_R  EQU 0x400253FC
GPIO_PORTF_DIR_R   EQU 0x40025400
GPIO_PORTF_AFSEL_R EQU 0x40025420
GPIO_PORTF_PUR_R   EQU 0x40025510
GPIO_PORTF_DEN_R   EQU 0x4002551C
GPIO_PORTF_LOCK_R  EQU 0x40025520
GPIO_PORTF_CR_R    EQU 0x40025524
GPIO_LOCK_KEY      EQU 0x4C4F434B  ; Unlocks the GPIO_CR register
SYSCTL_RCGCGPIO_R  EQU 0x400FE608

       IMPORT  TExaS_Init
       THUMB
       AREA    DATA, ALIGN=2
;global variables go here

       AREA    |.text|, CODE, READONLY, ALIGN=2
       THUMB

       EXPORT  Start

Start
			; TExaS_Init sets bus clock at 80 MHz
			BL  TExaS_Init
			; voltmeter, scope on PD3
;************************************************************************************************************	
; Initialization 
 
			; Turn on the clock
			LDR		R0, =SYSCTL_RCGCGPIO_R
			LDR		R1, [R0]
			ORR		R1, #0x30 						
			STR		R1, [R0]
		
			; Wait for clock to initialize
			NOP
			NOP
			
			;Define inputs and outputs (DIR)
			LDR		R0, =GPIO_PORTE_DIR_R
			LDRB	R1, [R0]
			AND		R1, #0x02						; Make PE1 as input
			ORR		R1, #0x04						; Make PE2 as output
			STRB	R1, [R0]

			LDR		R0, =GPIO_PORTF_DIR_R			
			LDRB	R1, [R0]
			AND		R1, #0x10		;PREV: BIC R1, #0x10				; Make PE4 as input
			STRB	R1, [R0]
		
			; Digitally enable pins (DEN)
			LDR		R0, =GPIO_PORTE_DEN_R			; Enable pins PE1 and PE2
			LDRB	R1, [R0]
			ORR		R1, #0x06
			STRB	R1, [R0]
		
			LDR		R0, =GPIO_PORTF_DEN_R			; Enable PF4 pin
			LDRB	R1, [R0]
			ORR		R1, #0x10
			STRB	R1, [R0]
			
			; Pull Up Resistor (PUR)- Gives board switch inputs an internal pull-up resistor
			LDR 	R0, =GPIO_PORTF_PUR_R
			LDRB	R1, [R0]
			ORR		R1, #0x10
			STR 	R1, [R0]
			
			CPSIE  I    							; TExaS voltmeter, scope runs on interrupts
			
;*************************************************************************************************************			

			MOV 	R3, #300						; initializes duty cycle to On 30%, Off 70%
			MOV 	R4, #700						; Note: R3 and R4 are reserved for on/off duty cycles, respectively
			MOV		R5, #0							; R5 = 1 if button pressed, 0 otherwise
			
; This is the main engine which keeps the LED toggling ON and OFF

loop
			MOV		R2, R4
loop1  		BL		checkInput						; checks whether button is pressed
			BL		delay							; delay 1 ms
			SUBS	R2, #1							; R2 contains the time (ms) left in OFF duty 
			BNE		loop1
			BL  	turnOnLED
			
			MOV		R2, R3							
loop2		BL		checkInput
			BL		delay							
			SUBS	R2, #1							; R2 contains the time (ms) left in ON duty 
			BNE		loop2
			BL		turnOffLED
			
			B 		loop	

*****************************************************************************************************************
; The program enters this phase if PE2 is pressed, and exits when it is released
Pressed		MOV		R5, #1							; R5 = 1 if pressed, 0 otherwise
wait2		BL		checkInput						; check if button is released
			SUBS	R5, #0
			BNE		wait2							
			B		modDutyCycle					; if button released, modify duty cycle
			
			
modDutyCycle
			ADD		R3, #200						; 20% increase for ON duty cycle, vice versa for OFF
			SUBS	R4, #200
			MOV		R0, #1100
			CMP		R3, R0							; is R3 (ON duty cycle) = 550 ms (110%)?
			BNE		loop							; if not, skip
			MOV		R3, #100						; resets duty cycle to 10% ON, 90% OFF
			MOV		R4, #900
			B		loop
*******************************************************************************************************************			

; This subroutine goes to label "Pressed" or "BreathingLED" if a button pressed, otherwise R5 = 0 and return
checkInput	LDR		R0, =GPIO_PORTF_DATA_R			
			LDR		R1, [R0]					
			AND		R1, #0x10						; Isolate input PF4
			SUBS	R1, #0							; If PE4 = 0 (negative logic), make LED breathe
			PUSH	{LR, R0}
			BEQ		BreathingLED
			POP		{LR, R0}
			
			LDR		R0, =GPIO_PORTE_DATA_R
			LDR		R1, [R0]
			AND		R1, #0x2						; Isolate input PE2
			SUBS	R1, #0							; If PE2 != 0, button is pressed
			BNE		Pressed
			MOV		R5, #0	
			BX		LR

*******************************************************************************************************************
; This subroutine makes the LED breathe
; R6: Reserved Duty Cycle (RDC) ON
; R7: Reserved Duty Cycle (RDC) OFF
; Breathing function is divided into 4 phases
; Phase 1: Increase Duty cycle from 10% to 90%, increments of  10, .9 second duration, exit condition: R6=90
; Phase 2: Decrease Duty cycle from 90% to 30%, increments of  20, .3 second duration, exit condition: R6=30
; Phase 3: Increase Duty cycle from 30% to 90%, increments of  20, .3 second duration, exit condition: R6=90
; Phase 4: Decrease Duty cycle from 90% to 10%, increments of  10, .7 second duration, exit condition: R6=10
; Each phase follows the same basic template: phase'n', phase'n.1', and phase'n.2'
; Phase'n'   compares RDC ON to exit condition, increments RDC ON and RDC OFF
; Phase'nA' checks PF4 for button release, executes appropriate DC OFF duration
; Phase'nB' checks PF4 for button release, executes appropriate DC ON duration
; For these reasons, only phase1 will be commented in detail
BreathingLED	
				PUSH {LR, R10}			; LR stack save for nested subroutine call
				
RestartBreath 	MOV R6, #0				;clears RDC ON register
				MOV R7, #100			;clears RDC OFF register
				B phase1

terminateBreath POP {LR, R10}
				BX LR

phase1			CMP R6, #90				;compares RDC ON to phase1 exit condition
				BEQ phase2				;phase2 shift if exit condition is met
				ADD  R6, R6, #10		;increments RDC ON by 10
				SUBS R7, #10			;increments RDC OFF by -10
				MOV R9, R6
				MOV R8, R7
				BL checkPF4Input		;calls for button status check 
				CMP R5, #1				;comparison of PF4 (negative logic), terminates breathing if button was released (R5=1)
				BNE terminateBreath
				
phase1A			BL delay				;executes .5ms delay
				SUBS R8, #1				
				BHS phase1A						
				BL turnOnLED	
				BL checkPF4Input
				CMP R5, #1				
				BNE terminateBreath

phase1B			BL delay
				SUBS R9, #1
				BHS phase1B
				BL turnOffLED
				B phase1

phase2			CMP R6, #30
				BEQ phase3
				SUBS R6, #20
				ADD R7, R7, #20
				MOV R9, R6
				MOV R8, R7		
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase2A			BL delay
				SUBS R8, #1
				BHS phase2A
				BL turnOnLED
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase2B			BL delay
				SUBS R9, #1
				BHS phase2B
				BL turnOffLED
				B phase2
				
phase3			CMP R6, #90
				BEQ phase4
				ADD R6, R6, #20
				SUBS R7, #20
				MOV R9, R6
				MOV R8, R7
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase3A			BL delay
				SUBS R8, #1
				BHS phase3A
				BL turnOnLED
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase3B			BL delay
				SUBS R9, #1
				BHS phase3B
				BL turnOffLED
				B phase3
				
phase4			CMP R6, #10
				BEQ RestartBreath			;branches to reinitialize RDC ON and RDC OFF for BreathingLED restart if exit condition is met
				SUBS R6, #10
				ADD R7, R7, #10
				MOV R9, R6
				MOV R8, R7
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase4A			BL delay
				SUBS R8, #1
				BHS phase4A
				BL turnOnLED
				BL checkPF4Input
				CMP R5, #1
				BNE terminateBreath

phase4B			BL delay
				SUBS R9, #1
				BHS phase4B
				BL turnOffLED
				B phase4
			
********************************************************************************************************************
;This subroutine turns on the LED
checkPF4Input	LDR		R0, =GPIO_PORTF_DATA_R			
				LDR		R1, [R0]					
				AND		R1, #0x10						; Isolate input PF4
				CMP  	R1, #0							; If PF4 = 0 (negative logic), make LED breathe
				BEQ     continue
				B       terminate

continue        MOV R5, #1
				BX LR
				
terminate       MOV R5, #0
				BX LR
			

********************************************************************************************************************
;This subroutine turns on the LED
turnOnLED	LDR		R0, =GPIO_PORTE_DATA_R		
			MOV		R1, #0x4		
			STR		R1, [R0]
			BX 		LR
********************************************************************************************************************
; This subroutine turns off the LED
turnOffLED	LDR		R0, =GPIO_PORTE_DATA_R		
			MOV		R1, #0x0		
			STR		R1, [R0]
			BX 		LR
********************************************************************************************************************
; This subroutine delays 0.5 ms
delay		LDR		R0, =10000	
wait		SUBS	R0, #1
			BNE		wait
			BX		LR
********************************************************************************************************************			  
		ALIGN      ; make sure the end of this section is aligned
		END        ; end of file