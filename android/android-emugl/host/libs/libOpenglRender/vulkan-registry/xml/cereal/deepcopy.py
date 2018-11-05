# Copyright (c) 2018 The Android Open Source Project
# Copyright (c) 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from .common.codegen import CodeGen
from .common.vulkantypes import \
        VulkanAPI, makeVulkanTypeSimple, iterateVulkanType

from .wrapperdefs import VulkanWrapperGenerator

class DeepcopyCodegen(object):
    def __init__(self, cgen, inputVars, poolVarName, prefix):
        self.cgen = cgen
        self.inputVars = inputVars
        self.prefix = prefix
        self.poolVarName = poolVarName

        def makeAccess(varName, asPtr = True):
            return lambda t: self.cgen.generalAccess(t, parentVarName = varName, asPtr = asPtr)

        def makeLengthAccess(varName):
            return lambda t: self.cgen.generalLengthAccess(t, parentVarName = varName)

        self.exprAccessorLhs = makeAccess(self.inputVars[0])
        self.exprAccessorRhs = makeAccess(self.inputVars[1])

        self.exprAccessorValueLhs = makeAccess(self.inputVars[0], asPtr = False)
        self.exprAccessorValueRhs = makeAccess(self.inputVars[1], asPtr = False)

        self.lenAccessorLhs = makeLengthAccess(self.inputVars[0])
        self.lenAccessorRhs = makeLengthAccess(self.inputVars[1])

        self.checked = False

    def needSkip(self, vulkanType):
        if vulkanType.isNextPointer():
            return True
        return False

    def makeCastExpr(self, vulkanType):
        return "(%s)" % (
            self.cgen.makeCTypeDecl(vulkanType, useParamName=False))

    def makeNonConstCastForCopy(self, access, vulkanType):
        if vulkanType.staticArrExpr:
            casted = "%s(%s)" % (self.makeCastExpr(vulkanType.getForAddressAccess().getForNonConstAccess()), access)
        elif vulkanType.accessibleAsPointer():
            casted = "%s(%s)" % (self.makeCastExpr(vulkanType.getForNonConstAccess()), access)
        else:
            casted = "%s(%s)" % (self.makeCastExpr(vulkanType.getForAddressAccess().getForNonConstAccess()), access)
        return casted

    def makeAllocBytesExpr(self, lenAccess, vulkanType):
        sizeof = self.cgen.sizeofExpr( \
                     vulkanType.getForValueAccess())
        if lenAccess:
            bytesExpr = "%s * %s" % (lenAccess, sizeof)
        else:
            bytesExpr = sizeof

        return bytesExpr

    def onCheck(self, vulkanType):
        pass

    def endCheck(self, vulkanType):
        pass

    def onCompoundType(self, vulkanType):

        if self.needSkip(vulkanType):
            self.cgen.line("// TODO: Unsupported : %s" %
                           self.cgen.makeCTypeDecl(vulkanType))
            return

        accessLhs = self.exprAccessorLhs(vulkanType)
        accessRhs = self.exprAccessorRhs(vulkanType)

        lenAccessLhs = self.lenAccessorLhs(vulkanType)
        lenAccessRhs = self.lenAccessorRhs(vulkanType)

        isPtr = vulkanType.pointerIndirectionLevels > 0

        if isPtr:
            self.cgen.stmt("%s = nullptr" % accessRhs)
            self.cgen.beginIf(accessLhs)

            self.cgen.stmt( \
                "%s = %s%s->alloc(%s)" % \
                (accessRhs, self.makeCastExpr(vulkanType.getForNonConstAccess()),
                 self.poolVarName, self.makeAllocBytesExpr(lenAccessLhs, vulkanType)))

        if lenAccessLhs is not None:

            loopVar = "i"
            accessLhs = "%s + %s" % (accessLhs, loopVar)
            forInit = "uint32_t %s = 0" % loopVar
            forCond = "%s < (uint32_t)%s" % (loopVar, lenAccessLhs)
            forIncr = "++%s" % loopVar

            if isPtr:
                self.cgen.stmt("%s = %s" % (lenAccessRhs, lenAccessLhs))

            accessRhs = "%s + %s" % (accessRhs, loopVar)
            self.cgen.beginFor(forInit, forCond, forIncr)


        accessRhsCasted = self.makeNonConstCastForCopy(accessRhs, vulkanType)

        self.cgen.funcCall(None, self.prefix + vulkanType.typeName,
                           [self.poolVarName, accessLhs, accessRhsCasted])

        if lenAccessLhs is not None:
            self.cgen.endFor()

        if isPtr:
            self.cgen.endIf()

    def onString(self, vulkanType):
        accessLhs = self.exprAccessorLhs(vulkanType)
        accessRhs = self.exprAccessorRhs(vulkanType)

        self.cgen.stmt("%s = nullptr" % accessRhs)
        self.cgen.beginIf(accessLhs)

        self.cgen.stmt( \
            "%s = %s->strDup(%s)" % \
            (accessRhs,
             self.poolVarName,
             accessLhs))

        self.cgen.endIf()

    def onStringArray(self, vulkanType):
        accessLhs = self.exprAccessorLhs(vulkanType)
        accessRhs = self.exprAccessorRhs(vulkanType)

        lenAccessLhs = self.lenAccessorLhs(vulkanType)
        lenAccessRhs = self.lenAccessorRhs(vulkanType)

        self.cgen.stmt("%s = nullptr" % accessRhs)
        self.cgen.beginIf("%s && %s" % (accessLhs, lenAccessLhs))

        self.cgen.stmt( \
            "%s = %s->strDupArray(%s, %s)" % \
            (accessRhs,
             self.poolVarName,
             accessLhs,
             lenAccessLhs))

        self.cgen.endIf()

    def onStaticArr(self, vulkanType):
        accessLhs = self.exprAccessorLhs(vulkanType)
        accessRhs = self.exprAccessorRhs(vulkanType)

        lenAccessLhs = self.lenAccessorLhs(vulkanType)

        bytesExpr = self.makeAllocBytesExpr(lenAccessLhs, vulkanType)
        self.cgen.stmt("memcpy(%s, %s, %s)" % (accessRhs, accessLhs, bytesExpr))

    def onPointer(self, vulkanType):

        accessLhs = self.exprAccessorLhs(vulkanType)
        accessRhs = self.exprAccessorRhs(vulkanType)

        if self.needSkip(vulkanType):
            self.cgen.stmt("%s = %s" % (accessRhs, accessLhs))
            return

        lenAccessLhs = self.lenAccessorLhs(vulkanType)

        self.cgen.stmt("%s = nullptr" % accessRhs)
        self.cgen.beginIf(accessLhs)

        bytesExpr = self.makeAllocBytesExpr(lenAccessLhs, vulkanType)

        self.cgen.stmt( \
            "%s = %s%s->dupArray(%s, %s)" % \
            (accessRhs,
             self.makeCastExpr(vulkanType.getForNonConstAccess()),
             self.poolVarName,
             accessLhs,
             bytesExpr))

        self.cgen.endIf()

    def onValue(self, vulkanType):
        accessLhs = self.exprAccessorValueLhs(vulkanType)
        accessRhs = self.exprAccessorValueRhs(vulkanType)

        self.cgen.stmt("%s = %s" % (accessRhs, accessLhs))

class VulkanDeepcopy(VulkanWrapperGenerator):

    def __init__(self, module, typeInfo):
        VulkanWrapperGenerator.__init__(self, module, typeInfo)

        self.codegen = CodeGen()

        self.deepcopyPrefix = "deepcopy_"
        self.deepcopyVars = ["from", "to"]
        self.deepcopyPoolVarName = "pool"
        self.deepcopyPoolParam = \
            makeVulkanTypeSimple(False, "Pool", 1,
                                 self.deepcopyPoolVarName)
        self.voidType = makeVulkanTypeSimple(False, "void", 0)

        self.deepcopyCodegen = \
            DeepcopyCodegen(
                None,
                self.deepcopyVars,
                self.deepcopyPoolVarName,
                self.deepcopyPrefix)

        self.knownDefs = {}

    def onGenType(self, typeXml, name, alias):
        VulkanWrapperGenerator.onGenType(self, typeXml, name, alias)

        if name in self.knownDefs:
            return

        category = self.typeInfo.categoryOf(name)

        if category in ["struct", "union"] and not alias:

            structInfo = self.typeInfo.structs[name]

            typeFromName = \
                lambda varname: \
                    makeVulkanTypeSimple(varname == "from", name, 1, varname)

            deepcopyParams = \
                [self.deepcopyPoolParam] + \
                list(map(typeFromName, self.deepcopyVars))
                
            deepcopyPrototype = \
                VulkanAPI(self.deepcopyPrefix + name,
                          self.voidType,
                          deepcopyParams)

            def structDeepcopyDef(cgen):
                self.deepcopyCodegen.cgen = cgen
                for member in structInfo.members:
                    iterateVulkanType(self.typeInfo, member,
                                      self.deepcopyCodegen)

            self.module.appendHeader(
                self.codegen.makeFuncDecl(deepcopyPrototype))
            self.module.appendImpl(
                self.codegen.makeFuncImpl(deepcopyPrototype, structDeepcopyDef))

    def onGenCmd(self, cmdinfo, name, alias):
        VulkanWrapperGenerator.onGenCmd(self, cmdinfo, name, alias)
