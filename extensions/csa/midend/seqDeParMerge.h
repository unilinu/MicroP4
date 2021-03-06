/*
 * Author: Hardik Soni
 * Email: hks57@cornell.edu
 */

#ifndef _EXTENSIONS_CSA_MIDEND_SEQDEPARMERGE_H_ 
#define _EXTENSIONS_CSA_MIDEND_SEQDEPARMERGE_H_ 

#include "ir/ir.h"
#include "frontends/common/resolveReferences/resolveReferences.h"
#include "frontends/p4/typeChecking/typeChecker.h"
#include "frontends/p4/typeMap.h"

namespace CSA {

class SeqDeParMerge final : public Transform {
    P4::ReferenceMap* refMap;
    P4::TypeMap* typeMap;
    const IR::P4ComposablePackage* cp2;

  public:
    explicit SeqDeParMerge(P4::ReferenceMap* refMap, P4::TypeMap* typeMap, 
      const IR::P4ComposablePackage* cp2) 
      : refMap(refMap), typeMap(typeMap), cp2(cp2) {
        CHECK_NULL(refMap); CHECK_NULL(typeMap);
        CHECK_NULL(cp2);
        setName("SeqDeParMerge"); 
    }

    const IR::Node* preorder(IR::P4Control* p4control) override;
    const IR::Node* postorder(IR::P4Control* p4control) override;

    const IR::Node* preorder(IR::P4Parser* p4parser) override;
    const IR::Node* postorder(IR::P4Parser* p4parser) override;

    const IR::Node* preorder(IR::P4ComposablePackage* cp) override;
    const IR::Node* postorder(IR::P4ComposablePackage* cp) override;

};

}   // namespace CSA
#endif  /* _EXTENSIONS_CSA_MIDEND_SEQDEPARMERGE_H_ */

