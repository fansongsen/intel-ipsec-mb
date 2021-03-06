;;
;; Copyright (c) 2017, Intel Corporation
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are met:
;;
;;     * Redistributions of source code must retain the above copyright notice,
;;       this list of conditions and the following disclaimer.
;;     * Redistributions in binary form must reproduce the above copyright
;;       notice, this list of conditions and the following disclaimer in the
;;       documentation and/or other materials provided with the distribution.
;;     * Neither the name of Intel Corporation nor the names of its contributors
;;       may be used to endorse or promote products derived from this software
;;       without specific prior written permission.
;;
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
;; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
;; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
;; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
;; OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;

%include "os.asm"
%include "memcpy.asm"

;;; Routine to do 128 bit CFB AES encrypt/decrypt operations on one block only.
;;; It processes only one buffer at a time.
;;; It is designed to manage partial blocks of DOCSIS 3.1 SEC BPI

;; In System V AMD64 ABI
;;	calle saves: RBX, RBP, R12-R15
;; Windows x64 ABI
;;	calle saves: RBX, RBP, RDI, RSI, RSP, R12-R15
;;
;; Registers:		RAX RBX RCX RDX RBP RSI RDI R8  R9  R10 R11 R12 R13 R14 R15
;;			-----------------------------------------------------------
;; Windows clobbers:	RAX                             R9  R10 R11
;; Windows preserves:	    RBX RCX RDX RBP RSI RDI R8              R12 R13 R14 R15
;;			-----------------------------------------------------------
;; Linux clobbers:	RAX                             R9  R10
;; Linux preserves:	    RBX RCX RDX RBP RSI RDI R8          R11 R12 R13 R14 R15
;;			-----------------------------------------------------------
;;
;; Linux/Windows clobbers: xmm0
;;

%ifdef LINUX
%define arg1	rdi
%define arg2	rsi
%define arg3	rdx
%define arg4	rcx
%define arg5	r8
%else
%define arg1	rcx
%define arg2	rdx
%define arg3	r8
%define arg4	r9
%define arg5	[rsp + 5*8]
%endif

%define OUT	arg1
%define IN	arg2
%define IV	arg3
%define KEYS	arg4
%ifdef LINUX
%define LEN	arg5
%else
%define LEN2	arg5
%define LEN	r11
%endif

%define TMP0	rax
%define TMP1	r10
%define PTR0	rsp + _buffer

%define XDATA	xmm0

section .text

struc STACK
_buffer:	resq	2
_rsp_save:	resq	1
endstruc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; void aes_cfb_128_one(void *out, void *in, void *iv, void *keys)
;; arg 1: OUT : addr to put clear/cipher text out
;; arg 2: IN  : addr to take cipher/clear text from
;; arg 3: IV  : initialization vector
;; arg 4: KEYS: pointer to expanded keys structure (16 byte aligned)
;; arg 5: LEN:  length of the text to encrypt/decrypt (valid range is 0 to 16)
;;
;; AES CFB128 one block encrypt/decrypt implementation.
;; The function doesn't update IV. The result of operation can be found in OUT.
;;
;; It is primarly designed to process partial block of
;; DOCSIS 3.1 AES Packet PDU Encryption (I.10)
;;
;; It process up to one block only (up to 16 bytes).
;;
;; It makes sure not to read more than LEN bytes from IN and
;; not to store more than LEN bytes to OUT.

MKGLOBAL(aes_cfb_128_one_sse,function,internal)
align 32
aes_cfb_128_one_sse:
%ifndef LINUX
	mov		LEN, LEN2
%endif
        mov		rax, rsp
        sub		rsp, STACK_size
        and		rsp, -16
	mov		[rsp + _rsp_save], rax

	test		LEN, 16
	jz		copy_in_lt16
	movdqu		XDATA, [IN]
	movdqa		[PTR0], XDATA
	jmp		copy_in_end
copy_in_lt16:
	memcpy_sse_16	PTR0, IN, LEN, TMP0, TMP1
copy_in_end:

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	movdqu		XDATA, [IV] 		; IV (or next to last block)
	pxor		XDATA, [KEYS + 16*0]	; 0. ARK
	aesenc		XDATA, [KEYS + 16*1]	; 1. ENC
	aesenc		XDATA, [KEYS + 16*2]	; 2. ENC
	aesenc		XDATA, [KEYS + 16*3]	; 3. ENC
	aesenc		XDATA, [KEYS + 16*4]	; 4. ENC
	aesenc		XDATA, [KEYS + 16*5]	; 5. ENC
	aesenc		XDATA, [KEYS + 16*6]	; 6. ENC
	aesenc		XDATA, [KEYS + 16*7]	; 7. ENC
	aesenc		XDATA, [KEYS + 16*8]	; 8. ENC
	aesenc		XDATA, [KEYS + 16*9]	; 9. ENC
	aesenclast	XDATA, [KEYS + 16*10]	; 10. ENC

	pxor		XDATA, [PTR0] 		; plaintext/ciphertext XOR block cipher encryption

	test		LEN, 16
	jz		copy_out_lt16
	movdqu		[OUT], XDATA
	jmp		copy_out_end
copy_out_lt16:
	movdqa		[PTR0], XDATA
	memcpy_sse_16	OUT, PTR0, LEN, TMP0, TMP1
copy_out_end:

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	mov		rsp, [rsp + _rsp_save]	; original SP
	ret
