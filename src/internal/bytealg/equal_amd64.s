// Copyright 2018 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "go_asm.h"
#include "textflag.h"

// memequal(a, b unsafe.Pointer, size uintptr) bool
TEXT runtime·memequal<ABIInternal>(SB),NOSPLIT,$0-25
	// AX = a    (want in SI)
	// BX = b    (want in DI)
	// CX = size (want in BX)
	CMPQ	AX, BX
	JE	eq
	MOVQ	AX, SI
	MOVQ	BX, DI
	MOVQ	CX, BX
	JMP	memeqbody<>(SB)
eq:
	SETEQ	AX	// return 1
	RET

// memequal_varlen(a, b unsafe.Pointer) bool
TEXT runtime·memequal_varlen<ABIInternal>(SB),NOSPLIT,$0-17
	// AX = a       (want in SI)
	// BX = b       (want in DI)
	// 8(DX) = size (want in BX)
	CMPQ	AX, BX
	JE	eq
	MOVQ	AX, SI
	MOVQ	BX, DI
	MOVQ	8(DX), BX    // compiler stores size at offset 8 in the closure
	JMP	memeqbody<>(SB)
eq:
	SETEQ	AX	// return 1
	RET

// Input:
//   a in SI
//   b in DI
//   count in BX
// Output:
//   result in AX
TEXT memeqbody<>(SB),NOSPLIT,$0-0
	CMPQ	BX, $8
	JA	over8
	JE	eight

	// check if length is zero
	CMPQ	BX, $0
	JE	equal

	// length is <= 8 bytes at this point
	LEAQ	0(BX*8), CX
	NEGQ	CX
	CMPB	SI, $0xf8
	JA	si_high
	// load at SI won't cross a page boundary.
	MOVQ	(SI), SI
	JMP	si_finish

over8: // length > 8 bytes
	CMPQ	BX, $64
	JB	over8loop_entrypoint
	JE	sixtyfour
	// check if AVX2 is present.
	CMPB	internal∕cpu·X86+const_offsetX86HasAVX2(SB), $1
	JE	over64loop_avx2_entrypoint
	JMP	over64loop_entrypoint

over64loop: // length > 64 bytes
	CMPQ	BX, $64
	JB	over8loop
	JE	sixtyfour
over64loop_entrypoint: // compare 64 bytes at a time using xmm registers
	MOVOU	(SI), X0
	MOVOU	(DI), X1
	MOVOU	16(SI), X2
	MOVOU	16(DI), X3
	MOVOU	32(SI), X4
	MOVOU	32(DI), X5
	MOVOU	48(SI), X6
	MOVOU	48(DI), X7
	PCMPEQB	X1, X0
	PCMPEQB	X3, X2
	PCMPEQB	X5, X4
	PCMPEQB	X7, X6
	PAND	X2, X0
	PAND	X6, X4
	PAND	X4, X0
	PMOVMSKB X0, DX
	ADDQ	$64, SI
	ADDQ	$64, DI
	SUBQ	$64, BX
	CMPL	DX, $0xffff
	JEQ	over64loop
	XORQ	AX, AX	// return 0
	RET

over64loop_avx2: // length > 64 bytes
	CMPQ	BX, $64
	JB	over8loop_avx2
	JE	sixtyfour
over64loop_avx2_entrypoint: // compare 64 bytes at a time using ymm registers
	VMOVDQU	(SI), Y0
	VMOVDQU	(DI), Y1
	VMOVDQU	32(SI), Y2
	VMOVDQU	32(DI), Y3
	VPCMPEQB	Y1, Y0, Y4
	VPCMPEQB	Y2, Y3, Y5
	VPAND	Y4, Y5, Y6
	VPMOVMSKB Y6, DX
	ADDQ	$64, SI
	ADDQ	$64, DI
	SUBQ	$64, BX
	CMPL	DX, $0xffffffff
	JEQ	over64loop_avx2
	VZEROUPPER
	XORQ	AX, AX	// return 0
	RET

over8loop_avx2:
	VZEROUPPER

over8loop: // length > 8 bytes
	CMPQ	BX, $8
	JBE	under8
	JE	 eight
	CMPQ	BX, $32
	JE	thirtytwo
over8loop_entrypoint: // compare 8 bytes at a time using 64-bit register
	MOVQ	(SI), CX
	MOVQ	(DI), DX
	ADDQ	$8, SI
	ADDQ	$8, DI
	SUBQ	$8, BX
	CMPQ	CX, DX
	JEQ	over8loop
	XORQ	AX, AX	// return 0
	RET

under8: // length < 8 bytes
	MOVQ	-8(SI)(BX*1), CX
	MOVQ	-8(DI)(BX*1), DX
	CMPQ	CX, DX
	SETEQ	AX
	RET

sixtyfour: // length == 64 bytes
	MOVQ	(SI), AX
	MOVQ	(DI), BX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	AX, BX
	JNE	notequal
// length == 56 bytes
	MOVQ	(SI), CX
	MOVQ	(DI), DX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	CX, DX
	JNE	notequal
// length == 48 bytes
	MOVQ	(SI), AX
	MOVQ	(DI), BX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	AX, BX
	JNE	notequal
// length == 40 bytes
	MOVQ	(SI), CX
	MOVQ	(DI), DX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	CX, DX
	JNE	notequal
thirtytwo: // length == 32 bytes
	MOVQ	(SI), AX
	MOVQ	(DI), BX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	AX, BX
	JNE	notequal
// length == 24 bytes
	MOVQ	(SI), CX
	MOVQ	(DI), DX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	CX, DX
	JNE	notequal
// length == 16 bytes
	MOVQ	(SI), AX
	MOVQ	(DI), BX
	ADDQ	$8, SI
	ADDQ	$8, DI
	CMPQ	AX, BX
	JNE	notequal
eight: // length == 8 bytes
	MOVQ	(SI), CX
	MOVQ	(DI), DX
	CMPQ	CX, DX
	SETEQ	AX
	RET
notequal:
	XORQ	AX, AX	// return 0
	RET

si_high:
	// address ends in 11111xxx. Load up to bytes we want, move to correct position.
	MOVQ	-8(SI)(BX*1), SI
	SHRQ	CX, SI
si_finish:

	// same for DI.
	CMPB	DI, $0xf8
	JA	di_high
	MOVQ	(DI), DI
	JMP	di_finish
di_high:
	MOVQ	-8(DI)(BX*1), DI
	SHRQ	CX, DI
di_finish:

	SUBQ	SI, DI
	SHLQ	CX, DI
equal:
	SETEQ	AX
	RET
